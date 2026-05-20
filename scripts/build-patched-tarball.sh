#!/bin/bash
#
# Build a pre-patched tarball from Claude Desktop Windows msix
#
# This script extracts the Windows msix package, applies all Linux patches,
# and creates a distributable tarball. The tarball can then be packaged
# for any Linux distribution (Arch, Debian, Snap, Flatpak, etc.)
#
# Usage: ./scripts/build-patched-tarball.sh <msix_path> <output_dir>
#
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PATCHES_DIR="$PROJECT_DIR/patches"

# If patches dir is read-only (e.g. CI bind-mount), copy to a writable location
# so Nim can write .nimcache and compiled binaries alongside the sources.
if [ -d "$PATCHES_DIR" ] && ! touch "$PATCHES_DIR/.write-test" 2>/dev/null; then
    WRITABLE_PATCHES="$(mktemp -d)/patches"
    cp -r "$PATCHES_DIR" "$WRITABLE_PATCHES"
    # Also copy js/ dir (Nim patches embed snippets via staticRead with ../js/ paths)
    [ -d "$PROJECT_DIR/js" ] && cp -r "$PROJECT_DIR/js" "$(dirname "$WRITABLE_PATCHES")/js"
    PATCHES_DIR="$WRITABLE_PATCHES"
else
    rm -f "$PATCHES_DIR/.write-test" 2>/dev/null
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Parse arguments
MSIX_PATH="$1"
OUTPUT_DIR="$2"

if [ -z "$MSIX_PATH" ] || [ -z "$OUTPUT_DIR" ]; then
    echo "Usage: $0 <msix_path> <output_dir>"
    echo ""
    echo "Arguments:"
    echo "  msix_path   Path to Claude.msix"
    echo "  output_dir  Directory to write tarball and extracted files"
    echo ""
    echo "Output:"
    echo "  <output_dir>/claude-desktop-<version>-linux.tar.gz"
    exit 1
fi

if [ ! -f "$MSIX_PATH" ]; then
    log_error "msix file not found: $MSIX_PATH"
    exit 1
fi

# Check dependencies
log_info "Checking dependencies..."
MISSING_DEPS=()
for dep in 7z asar python3; do
    if ! command -v "$dep" &> /dev/null; then
        MISSING_DEPS+=("$dep")
    fi
done

# convert (ImageMagick) is optional — used to resize the 300x300 logo to 256x256.
# If missing we copy the source PNG as-is.
if ! command -v convert &> /dev/null && ! command -v magick &> /dev/null; then
    log_warn "ImageMagick (convert/magick) not found — icon will be copied at 300x300 instead of 256x256"
fi

if [ ${#MISSING_DEPS[@]} -ne 0 ]; then
    log_error "Missing dependencies: ${MISSING_DEPS[*]}"
    echo "Install them with: sudo pacman -S p7zip imagemagick python"
    echo "For asar: yay -S asar (or npm install -g @electron/asar)"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"
WORK_DIR="$OUTPUT_DIR/work"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

# Extract the msix package (flat zip with app/, assets/, AppxManifest.xml)
log_info "Extracting msix package..."
7z x -y "$MSIX_PATH" -o"$WORK_DIR/extract" >/dev/null 2>&1

# msix encodes special chars in paths (e.g. `@` → `%40`, `@2x` → `%402x`).
# Asar needs `@scope` directories restored before it can resolve unpacked files,
# so URL-decode every path under extract/.
log_info "URL-decoding msix paths..."
python3 -c "
import os, urllib.parse
root = '$WORK_DIR/extract'
# Walk bottom-up so renaming a parent doesn't invalidate child paths.
for dirpath, dirnames, filenames in os.walk(root, topdown=False):
    for name in filenames + dirnames:
        decoded = urllib.parse.unquote(name)
        if decoded != name:
            os.rename(os.path.join(dirpath, name), os.path.join(dirpath, decoded))
"

# Resources live at app/resources/ in the msix layout
RES_DIR="$WORK_DIR/extract/app/resources"
if [ ! -f "$RES_DIR/app.asar" ]; then
    log_error "app.asar not found at $RES_DIR — is this a valid Claude msix?"
    exit 1
fi

# Extract version from AppxManifest.xml (Identity Version is X.Y.Z.0)
VERSION=$(python3 -c "
import re, xml.etree.ElementTree as ET
root = ET.parse('$WORK_DIR/extract/AppxManifest.xml').getroot()
ns = {'m': 'http://schemas.microsoft.com/appx/manifest/foundation/windows10'}
v = root.find('m:Identity', ns).attrib['Version']
print(re.sub(r'\.0$', '', v))
")
log_info "Detected version: $VERSION"

# Prepare app directory
log_info "Preparing app directory..."
mkdir -p "$WORK_DIR/app"
cp "$RES_DIR/app.asar" "$WORK_DIR/app/"
cp -r "$RES_DIR/app.asar.unpacked" "$WORK_DIR/app/" 2>/dev/null || true

# Extract app.asar for patching
log_info "Extracting app.asar..."
cd "$WORK_DIR/app"
asar extract app.asar app.asar.contents

# Copy i18n files into app.asar contents
log_info "Copying i18n files..."
mkdir -p app.asar.contents/resources/i18n
if ls "$RES_DIR"/*.json 1> /dev/null 2>&1; then
    cp "$RES_DIR"/*.json app.asar.contents/resources/i18n/
fi

# Compile Nim patches (native build or Docker fallback)
log_info "Compiling Nim patches..."
"$SCRIPT_DIR/compile-nim-patches.sh" "$PATCHES_DIR"

# Apply all patches via orchestrator
log_info "Applying patches..."
if ! python3 "$SCRIPT_DIR/apply_patches.py" "$PATCHES_DIR" "$WORK_DIR/app"; then
    log_error "One or more patches failed to apply"
    exit 1
fi

# Validate JavaScript syntax after patching
log_info "Validating JavaScript syntax..."
SYNTAX_FAILED=false
for js_file in "$WORK_DIR/app/app.asar.contents/.vite/build/"*.js; do
    [ -f "$js_file" ] || continue
    if ! node --check "$js_file" 2>/dev/null; then
        log_error "Syntax error in $(basename "$js_file")"
        SYNTAX_FAILED=true
    fi
done
for js_file in "$WORK_DIR/app/app.asar.contents/.vite/renderer/"*"/assets/"*.js; do
    [ -f "$js_file" ] || continue
    if ! node --check "$js_file" 2>/dev/null; then
        log_error "Syntax error in $(basename "$js_file")"
        SYNTAX_FAILED=true
    fi
done

if [ "$SYNTAX_FAILED" = true ]; then
    log_error "JavaScript syntax validation FAILED - patched files have syntax errors"
    exit 1
fi
log_info "JavaScript syntax validation passed"

# Remove Windows native binary (replaced by JS stubs in claude-native.js patch)
rm -f "$WORK_DIR/app/app.asar.contents/node_modules/@ant/claude-native/claude-native-binding.node"
rm -f "$WORK_DIR/app/app.asar.unpacked/node_modules/@ant/claude-native/claude-native-binding.node"

# Rebuild node-pty for Linux (upstream ships only Windows binaries)
# This enables the integrated terminal + read_terminal MCP tool
NODE_PTY_CONTENTS="$WORK_DIR/app/app.asar.contents/node_modules/node-pty"
NODE_PTY_UNPACKED="$WORK_DIR/app/app.asar.unpacked/node_modules/node-pty"
if [ -d "$NODE_PTY_UNPACKED" ] && command -v npx &>/dev/null; then
    log_info "Rebuilding node-pty for Linux..."
    # The extracted app only has prebuilt Windows binaries and lib/ (no source).
    # Install from npm with source, rebuild against Electron headers, then swap in.
    NODE_PTY_VERSION=$(node -e "console.log(require('$WORK_DIR/app/app.asar.contents/package.json').optionalDependencies?.['node-pty'] || '')" 2>/dev/null)
    ELECTRON_VERSION=$(node -e "console.log(require('$WORK_DIR/app/app.asar.contents/package.json').devDependencies?.electron || '')" 2>/dev/null)

    if [ -n "$NODE_PTY_VERSION" ] && [ -n "$ELECTRON_VERSION" ]; then
        PTY_BUILD_DIR=$(mktemp -d)
        (
            cd "$PTY_BUILD_DIR"
            npm init -y >/dev/null 2>&1
            npm install "node-pty@$NODE_PTY_VERSION" --ignore-scripts 2>&1 | tail -1
            npx @electron/rebuild --version "$ELECTRON_VERSION" \
                --module-dir node_modules/node-pty --arch x64 2>&1 | tail -3
        )

        REBUILT_PTY="$PTY_BUILD_DIR/node_modules/node-pty/build/Release/pty.node"
        if [ -f "$REBUILT_PTY" ] && file "$REBUILT_PTY" | grep -q "ELF 64-bit"; then
            # Build spawn-helper from source (needed by pty.fork() to spawn PTY processes)
            # @electron/rebuild only builds .node modules, not executables
            SPAWN_HELPER_SRC="$PTY_BUILD_DIR/node_modules/node-pty/src/unix/spawn-helper.cc"
            SPAWN_HELPER_BIN="$PTY_BUILD_DIR/spawn-helper"
            if [ -f "$SPAWN_HELPER_SRC" ] && command -v gcc &>/dev/null; then
                gcc -o "$SPAWN_HELPER_BIN" "$SPAWN_HELPER_SRC" 2>&1
            fi

            # Replace Windows binaries in asar contents with Linux builds
            # This is critical: .node files inside the asar can't be dlopen'd by Electron.
            # The --unpack flag in the asar pack step below moves them to app.asar.unpacked/
            rm -f "$NODE_PTY_CONTENTS/build/Release/"*.exe
            rm -f "$NODE_PTY_CONTENTS/build/Release/"*.dll
            rm -f "$NODE_PTY_CONTENTS/build/Release/conpty"*.node
            rm -f "$NODE_PTY_CONTENTS/build/Release/pty.node"
            cp "$REBUILT_PTY" "$NODE_PTY_CONTENTS/build/Release/pty.node"
            if [ -f "$SPAWN_HELPER_BIN" ]; then
                cp "$SPAWN_HELPER_BIN" "$NODE_PTY_CONTENTS/build/Release/spawn-helper"
                log_info "node-pty + spawn-helper rebuilt successfully ($(file -b "$REBUILT_PTY" | cut -d, -f1-2))"
            else
                log_warn "spawn-helper build failed — terminal may not spawn shells"
                log_info "node-pty rebuilt successfully ($(file -b "$REBUILT_PTY" | cut -d, -f1-2))"
            fi

            # Also update the unpacked dir (used by rebuild-pty-for-arch.sh)
            rm -f "$NODE_PTY_UNPACKED/build/Release/"*.node
            rm -f "$NODE_PTY_UNPACKED/build/Release/"*.exe
            rm -f "$NODE_PTY_UNPACKED/build/Release/"*.dll
            mkdir -p "$NODE_PTY_UNPACKED/build/Release"
            cp "$REBUILT_PTY" "$NODE_PTY_UNPACKED/build/Release/pty.node"
            [ -f "$SPAWN_HELPER_BIN" ] && cp "$SPAWN_HELPER_BIN" "$NODE_PTY_UNPACKED/build/Release/spawn-helper"
        else
            log_warn "node-pty rebuild failed — integrated terminal will be unavailable"
        fi
        rm -rf "$PTY_BUILD_DIR"
    else
        log_warn "Could not detect node-pty or Electron version — skipping rebuild"
    fi
else
    if [ ! -d "$NODE_PTY_UNPACKED" ]; then
        log_warn "node-pty not found in app.asar.unpacked — skipping rebuild"
    else
        log_warn "npx not available — skipping node-pty rebuild"
    fi
fi

# Remove remaining Windows .node/.exe/.dll from asar contents
# Native .node files can't be loaded from inside an asar archive —
# they must live in app.asar.unpacked/ (handled by --unpack below)
log_info "Cleaning Windows native binaries from asar contents..."
find "$WORK_DIR/app/app.asar.contents" \( -name "*.exe" -o -name "*.dll" \) -delete 2>/dev/null || true

# Repack app.asar
# --unpack ensures native .node files and spawn-helper are placed in app.asar.unpacked/
# and marked in the asar header so Electron redirects require() to the unpacked location
log_info "Repacking app.asar..."
cd "$WORK_DIR/app"
asar pack app.asar.contents app.asar --unpack "{**/*.node,**/spawn-helper}"
rm -rf app.asar.contents

# Copy all upstream resources to locales/ (must be in place before smoke test)
# This is future-proof: new resources Anthropic adds are automatically included.
# Electron's process.resourcesPath is patched to resolve to this locales/ dir.
log_info "Copying upstream resources to locales/..."
mkdir -p "$WORK_DIR/app/locales"
cp -r "$RES_DIR"/* "$WORK_DIR/app/locales/"

# Remove items already handled separately or Windows-only
rm -rf "$WORK_DIR/app/locales/app.asar" "$WORK_DIR/app/locales/app.asar.unpacked"
find "$WORK_DIR/app/locales" \( -name "*.exe" -o -name "*.dll" -o -name "*.vhdx" -o -name "*.ico" \) -delete

# Ensure claude-ssh binaries are executable
chmod +x "$WORK_DIR/app/locales/claude-ssh/claude-ssh-"* 2>/dev/null || true

# Apply ion-dist patches (the SPA has content-hashed filenames, so the patch
# finds its target file dynamically by grepping for a unique pattern)
ION_DIST_DIR="$WORK_DIR/app/locales/ion-dist"
ION_DIST_PATCH="$PATCHES_DIR/fix_ion_dist_linux"
if [ -d "$ION_DIST_DIR" ] && [ -x "$ION_DIST_PATCH" ]; then
    log_info "Applying ion-dist patches..."
    if ! "$ION_DIST_PATCH" "$ION_DIST_DIR"; then
        log_error "ion-dist patch failed"
        exit 1
    fi
elif [ -d "$ION_DIST_DIR" ]; then
    log_warn "ion-dist found but patch binary not available - skipping"
else
    log_warn "ion-dist not found in upstream resources - skipping"
fi

# Copy smol-bin VM image(s) — Desktop's startVM copies these from
# process.resourcesPath into the per-session bundle dir as
# `smol-bin.vhdx`, which the claude-cowork-service daemon then converts
# to qcow2 on first boot. Without this, the guest boots without the SDK
# binary disk and every spawn fails with "claude: No such file".
# In the msix layout the vhdx ships at app/resources/smol-bin.*.vhdx.
log_info "Copying smol-bin VM image(s)..."
SMOL_FOUND=0
for src in "$RES_DIR"/smol-bin.*.vhdx; do
    [ -f "$src" ] || continue
    cp "$src" "$WORK_DIR/app/locales/"
    log_info "  -> $(basename "$src")"
    SMOL_FOUND=1
done
if [ "$SMOL_FOUND" = 0 ]; then
    log_error "No smol-bin.*.vhdx found at $RES_DIR — VM guest will fail to boot"
    exit 1
fi

# Run Electron smoke test if dependencies are available
if [ "${SKIP_SMOKE_TEST:-0}" = "1" ]; then
    log_warn "Skipping smoke test (SKIP_SMOKE_TEST=1)"
elif command -v electron &>/dev/null && command -v xvfb-run &>/dev/null; then
    log_info "Running Electron smoke test..."
    if ! "$SCRIPT_DIR/smoke-test.sh" "$WORK_DIR/app/app.asar"; then
        log_error "Smoke test FAILED - the patched app crashes on startup"
        exit 1
    fi
else
    log_warn "Skipping smoke test (install electron and xorg-server-xvfb to enable)"
fi

# Create tarball structure
log_info "Creating tarball structure..."
TARBALL_DIR="$WORK_DIR/tarball"
mkdir -p "$TARBALL_DIR/app" "$TARBALL_DIR/icons" "$TARBALL_DIR/launcher"

# Copy patched app
cp -r "$WORK_DIR/app"/* "$TARBALL_DIR/app/"

# Copy launcher script
cp "$SCRIPT_DIR/claude-desktop-launcher.sh" "$TARBALL_DIR/launcher/claude-desktop"
chmod +x "$TARBALL_DIR/launcher/claude-desktop"

# Bundle kwin-portal-bridge into locales/ (= process.resourcesPath at runtime)
if [ -n "${KWIN_PORTAL_BRIDGE_BIN:-}" ] && [ -f "$KWIN_PORTAL_BRIDGE_BIN" ]; then
    log_info "Bundling kwin-portal-bridge from $KWIN_PORTAL_BRIDGE_BIN"
    cp "$KWIN_PORTAL_BRIDGE_BIN" "$TARBALL_DIR/app/locales/kwin-portal-bridge"
    chmod +x "$TARBALL_DIR/app/locales/kwin-portal-bridge"
elif command -v cargo &>/dev/null && [ -d "$PROJECT_DIR/../kwin-portal-bridge" ]; then
    log_info "Building kwin-portal-bridge from source..."
    if (cd "$PROJECT_DIR/../kwin-portal-bridge" && cargo build --release 2>&1 | tail -3); then
        cp "$PROJECT_DIR/../kwin-portal-bridge/target/release/kwin-portal-bridge" "$TARBALL_DIR/app/locales/kwin-portal-bridge"
        chmod +x "$TARBALL_DIR/app/locales/kwin-portal-bridge"
        log_info "kwin-portal-bridge built and bundled"
    else
        log_warn "kwin-portal-bridge build failed — skipping (KDE Wayland Computer Use will require manual install)"
    fi
else
    log_warn "kwin-portal-bridge not available — skipping (KDE Wayland Computer Use will require manual install)"
fi

# Validate launcher with shellcheck (catches shebang issues, syntax errors, common bugs)
if command -v shellcheck &>/dev/null; then
    if ! shellcheck -S error "$TARBALL_DIR/launcher/claude-desktop"; then
        log_error "Launcher failed shellcheck — fix scripts/claude-desktop-launcher.sh"
        exit 1
    fi
    log_info "Launcher passed shellcheck"
else
    log_warn "shellcheck not installed — skipping launcher validation"
fi

# Validate .desktop entry from PKGBUILD.template
# The .desktop file is generated at install time by PKGBUILD, not shipped in the tarball.
# We extract and validate it here to catch spec violations (like invalid Path= values)
# before they reach users.
if command -v desktop-file-validate &>/dev/null; then
    DESKTOP_TMP="$WORK_DIR/claude-desktop.desktop"
    sed -n '/^\[Desktop Entry\]/,/^EOF$/p' "$PROJECT_DIR/PKGBUILD.template" | head -n -1 > "$DESKTOP_TMP"
    DESKTOP_WARNINGS=$(desktop-file-validate "$DESKTOP_TMP" 2>&1 | grep -c "warning:" || true)
    if [ "$DESKTOP_WARNINGS" -gt 0 ]; then
        log_error ".desktop file has validation warnings:"
        desktop-file-validate "$DESKTOP_TMP" 2>&1 | grep "warning:" >&2
        rm -f "$DESKTOP_TMP"
        exit 1
    fi
    rm -f "$DESKTOP_TMP"
    log_info ".desktop file passed validation"
else
    log_warn "desktop-file-validate not installed — skipping .desktop validation"
fi

# Extract icon — msix ships pre-rendered PNGs in assets/.
# Square150x150Logo.png is 300x300; resize to 256x256 for the hicolor theme.
ICON_SRC="$WORK_DIR/extract/assets/Square150x150Logo.png"
ICON_DST="$TARBALL_DIR/icons/claude-desktop.png"
if [ -f "$ICON_SRC" ]; then
    if command -v magick &>/dev/null; then
        magick "$ICON_SRC" -resize 256x256 "$ICON_DST"
    elif command -v convert &>/dev/null; then
        convert "$ICON_SRC" -resize 256x256 "$ICON_DST"
    else
        cp "$ICON_SRC" "$ICON_DST"
    fi
else
    log_warn "Icon source not found at $ICON_SRC — package will ship without an icon"
fi

# Create the tarball
TARBALL_FILE="$OUTPUT_DIR/claude-desktop-${VERSION}-linux.tar.gz"
log_info "Creating tarball: $TARBALL_FILE"
cd "$TARBALL_DIR"
tar -czvf "$TARBALL_FILE" app/ icons/ launcher/

# Calculate SHA256
SHA256=$(sha256sum "$TARBALL_FILE" | cut -d' ' -f1)

# Clean up work directory
rm -rf "$WORK_DIR"

# Output results
echo ""
log_info "Build complete!"
echo "  Version:  $VERSION"
echo "  Tarball:  $TARBALL_FILE"
echo "  SHA256:   $SHA256"

# Write metadata file for CI
cat > "$OUTPUT_DIR/build-info.txt" << EOF
VERSION="$VERSION"
TARBALL="$TARBALL_FILE"
SHA256="$SHA256"
EOF
