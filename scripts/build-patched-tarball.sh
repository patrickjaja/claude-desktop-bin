#!/bin/bash
#
# Build a pre-patched tarball from Claude Desktop Windows exe
#
# This script extracts the Windows installer, applies all Linux patches,
# and creates a distributable tarball. The tarball can then be packaged
# for any Linux distribution (Arch, Debian, Snap, Flatpak, etc.)
#
# Usage: ./scripts/build-patched-tarball.sh [--electron=<bundled|system>] <exe_path> <output_dir>
#
#   --electron=bundled  (default)  Ship the matching Electron runtime inside
#                                  the tarball. Larger artifact (~80 MB extra)
#                                  but the app runs without any host Electron
#                                  installed.
#   --electron=system              Don't ship Electron. The launcher picks up
#                                  `electron` from $PATH (or /usr/lib/claude-
#                                  desktop/electron). Smaller tarball, matches
#                                  master-branch behaviour.
#
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PATCHES_DIR="$PROJECT_DIR/patches"
ELECTRON_CACHE_DIR="$PROJECT_DIR/cache"

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
ELECTRON_MODE="bundled"
POSITIONAL=()
while [ $# -gt 0 ]; do
    case "$1" in
        --electron=*)
            ELECTRON_MODE="${1#*=}"
            shift
            ;;
        --electron)
            ELECTRON_MODE="$2"
            shift 2
            ;;
        --help|-h)
            sed -n '1,/^set -e$/p' "$0" | sed 's/^# \?//' | head -n -1
            exit 0
            ;;
        *)
            POSITIONAL+=("$1")
            shift
            ;;
    esac
done

case "$ELECTRON_MODE" in
    bundled|system) ;;
    *)
        log_error "Invalid --electron value: '$ELECTRON_MODE' (expected 'bundled' or 'system')"
        exit 1
        ;;
esac

EXE_PATH="${POSITIONAL[0]:-}"
OUTPUT_DIR="${POSITIONAL[1]:-}"

if [ -z "$EXE_PATH" ] || [ -z "$OUTPUT_DIR" ]; then
    echo "Usage: $0 [--electron=<bundled|system>] <exe_path> <output_dir>"
    echo ""
    echo "Arguments:"
    echo "  exe_path    Path to Claude-Setup-x64.exe"
    echo "  output_dir  Directory to write tarball and extracted files"
    echo ""
    echo "Options:"
    echo "  --electron=bundled  (default)  Ship matching Electron with the tarball"
    echo "  --electron=system              Use system electron (matches master branch)"
    echo ""
    echo "Output:"
    echo "  <output_dir>/claude-desktop-<version>-linux.tar.gz"
    exit 1
fi

if [ ! -f "$EXE_PATH" ]; then
    log_error "Exe file not found: $EXE_PATH"
    exit 1
fi

# Check dependencies
log_info "Checking dependencies..."
MISSING_DEPS=()
for dep in 7z asar python3 icotool; do
    if ! command -v "$dep" &> /dev/null; then
        MISSING_DEPS+=("$dep")
    fi
done

if [ ${#MISSING_DEPS[@]} -ne 0 ]; then
    log_error "Missing dependencies: ${MISSING_DEPS[*]}"
    echo "Install them with: sudo pacman -S p7zip icoutils python"
    echo "For asar: yay -S asar (or npm install -g @electron/asar)"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"
WORK_DIR="$OUTPUT_DIR/work"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
if [ "$ELECTRON_MODE" = "bundled" ]; then
    mkdir -p "$ELECTRON_CACHE_DIR"
fi

log_info "Electron mode: $ELECTRON_MODE"

# Extract the Windows installer
log_info "Extracting Windows installer..."
7z x -y "$EXE_PATH" -o"$WORK_DIR/extract" >/dev/null 2>&1

# Extract the nupkg
log_info "Extracting nupkg..."
cd "$WORK_DIR/extract"
NUPKG=$(find . -maxdepth 1 -name "AnthropicClaude-*.nupkg" | head -1)
if [ -z "$NUPKG" ]; then
    log_error "No nupkg found in installer"
    exit 1
fi
7z x -y "$NUPKG" >/dev/null 2>&1

# Extract version from nupkg filename
VERSION=$(echo "$NUPKG" | sed -E 's/.*AnthropicClaude-([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
log_info "Detected version: $VERSION"

# Prepare app directory
log_info "Preparing app directory..."
mkdir -p "$WORK_DIR/app"
cp "lib/net45/resources/app.asar" "$WORK_DIR/app/"
cp -r "lib/net45/resources/app.asar.unpacked" "$WORK_DIR/app/" 2>/dev/null || true

# Extract app.asar for patching
log_info "Extracting app.asar..."
cd "$WORK_DIR/app"
asar extract app.asar app.asar.contents

# Copy i18n files into app.asar contents
log_info "Copying i18n files..."
mkdir -p app.asar.contents/resources/i18n
if ls "$WORK_DIR/extract/lib/net45/resources/"*.json 1> /dev/null 2>&1; then
    cp "$WORK_DIR/extract/lib/net45/resources/"*.json app.asar.contents/resources/i18n/
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

if [ "$SYNTAX_FAILED" = true ]; then
    log_error "JavaScript syntax validation FAILED - patched files have syntax errors"
    exit 1
fi
log_info "JavaScript syntax validation passed"

# Remove Windows native binary (replaced by JS stubs in claude-native.js patch)
rm -f "$WORK_DIR/app/app.asar.contents/node_modules/@ant/claude-native/claude-native-binding.node"
rm -f "$WORK_DIR/app/app.asar.unpacked/node_modules/@ant/claude-native/claude-native-binding.node"

# Capture the Electron spec *now* — the app.asar.contents/ tree is about to
# be repacked and deleted. ELECTRON_MAJOR drives the runtime download later.
ELECTRON_SPEC=$(node -e "console.log(require('$WORK_DIR/app/app.asar.contents/package.json').devDependencies?.electron || '')" 2>/dev/null || true)
ELECTRON_MAJOR=$(echo "$ELECTRON_SPEC" | sed -E 's/^[~^=<>v ]+//' | cut -d. -f1)
if [ -z "$ELECTRON_MAJOR" ]; then
    log_error "Could not determine Electron major version from app.asar.contents/package.json (devDependencies.electron='$ELECTRON_SPEC')"
    exit 1
fi
log_info "App declares Electron major v$ELECTRON_MAJOR"

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

# Copy locales (must be in place before smoke test — app loads them on startup)
log_info "Copying locales..."
mkdir -p "$WORK_DIR/app/locales"
cp "$WORK_DIR/extract/lib/net45/resources/"*.json "$WORK_DIR/app/locales/" 2>/dev/null || true

# Copy tray icons
log_info "Copying tray icons..."
cp "$WORK_DIR/extract/lib/net45/resources/TrayIconTemplate"*.png "$WORK_DIR/app/locales/" 2>/dev/null || true

# Copy claude-ssh binaries (needed for SSH remote environment feature)
if [ -d "$WORK_DIR/extract/lib/net45/resources/claude-ssh" ]; then
    log_info "Copying claude-ssh binaries..."
    cp -r "$WORK_DIR/extract/lib/net45/resources/claude-ssh" "$WORK_DIR/app/locales/"
    chmod +x "$WORK_DIR/app/locales/claude-ssh/claude-ssh-"* 2>/dev/null || true
fi

# Copy cowork-plugin-shim.sh (needed for Cowork plugin/skill permission bridge)
# Electron's process.resourcesPath resolves to the locales/ dir in our layout
if [ -f "$WORK_DIR/extract/lib/net45/resources/cowork-plugin-shim.sh" ]; then
    log_info "Copying cowork-plugin-shim.sh..."
    cp "$WORK_DIR/extract/lib/net45/resources/cowork-plugin-shim.sh" "$WORK_DIR/app/locales/"
fi

# Copy smol-bin VM image(s) — Desktop's startVM copies these from
# process.resourcesPath into the per-session bundle dir as
# `smol-bin.vhdx`, which the claude-cowork-service daemon then converts
# to qcow2 on first boot. Without this, the guest boots without the SDK
# binary disk and every spawn fails with "claude: No such file".
# The Windows installer ships smol-bin.*.vhdx at lib/net45/ (alongside
# cowork-svc.exe), not inside resources/, so copy from either location.
log_info "Copying smol-bin VM image(s)..."
for src in \
    "$WORK_DIR/extract/lib/net45/smol-bin."*.vhdx \
    "$WORK_DIR/extract/lib/net45/resources/smol-bin."*.vhdx; do
    [ -f "$src" ] || continue
    cp "$src" "$WORK_DIR/app/locales/"
    log_info "  -> $(basename "$src")"
done

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

# Create tarball structure. Bundled mode ships a matching Electron runtime
# alongside the patched app (app/ = Electron binary + app/resources/<patched>);
# system mode ships only the patched app and relies on the user's Electron
# (app/ = patched app files, flat).
log_info "Creating tarball structure..."
TARBALL_DIR="$WORK_DIR/tarball"
mkdir -p "$TARBALL_DIR/icons" "$TARBALL_DIR/launcher"

if [ "$ELECTRON_MODE" = "bundled" ]; then
    # Resolve the latest stable Electron release matching $ELECTRON_MAJOR
    # (determined earlier, before app.asar.contents was packed away).
    log_info "Resolving latest stable Electron v$ELECTRON_MAJOR release..."
    ELECTRON_TAG=$(curl -sSL --fail "https://api.github.com/repos/electron/electron/releases?per_page=100" \
        | python3 -c '
import json, sys
major = sys.argv[1]
prefix = f"v{major}."
bad = ("-alpha", "-beta", "-rc", "-nightly")
for r in json.load(sys.stdin):
    t = r.get("tag_name", "")
    if t.startswith(prefix) and not r.get("prerelease", False) and not any(b in t for b in bad):
        print(t.lstrip("v"))
        break
' "$ELECTRON_MAJOR")

    if [ -z "$ELECTRON_TAG" ]; then
        log_error "No stable Electron v$ELECTRON_MAJOR release found on GitHub"
        exit 1
    fi
    log_info "Using Electron v$ELECTRON_TAG"

    # Cache the zip by version so reruns skip the ~80MB download.
    ELECTRON_CACHE_DIR="${ELECTRON_CACHE_DIR:-$OUTPUT_DIR}"
    ELECTRON_ZIP="$ELECTRON_CACHE_DIR/electron-v${ELECTRON_TAG}-linux-x64.zip"
    if [ ! -s "$ELECTRON_ZIP" ]; then
        log_info "Downloading Electron v$ELECTRON_TAG..."
        curl -L --fail --output "$ELECTRON_ZIP" \
            "https://github.com/electron/electron/releases/download/v${ELECTRON_TAG}/electron-v${ELECTRON_TAG}-linux-x64.zip"
    fi

    mkdir -p "$TARBALL_DIR/app/resources"
    unzip -q "$ELECTRON_ZIP" -d "$TARBALL_DIR/app"
    # Rename the Electron binary so systemd-run scopes and xdg-desktop-portal
    # identify the process via our reverse-URL APP_ID instead of "electron".
    mv "$TARBALL_DIR/app/electron" "$TARBALL_DIR/app/com.anthropic.claude-desktop"
    cp -r "$WORK_DIR/app"/* "$TARBALL_DIR/app/resources/"
else
    # System Electron: flat app/ layout, no Electron binary bundled.
    # `depends=(electron)` in PKGBUILD / package deps provides the runtime.
    mkdir -p "$TARBALL_DIR/app"
    cp -r "$WORK_DIR/app"/* "$TARBALL_DIR/app/"
fi

# Copy launcher script
cp "$SCRIPT_DIR/claude-desktop-launcher.sh" "$TARBALL_DIR/launcher/claude-desktop"
chmod +x "$TARBALL_DIR/launcher/claude-desktop"

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

# Extract icon
if [ -f "$WORK_DIR/extract/setupIcon.ico" ]; then
    icotool -x -o "$TARBALL_DIR/icons/" "$WORK_DIR/extract/setupIcon.ico"
    # Use the 256x256 icon
    mv "$TARBALL_DIR/icons/setupIcon_6_256x256x32.png" "$TARBALL_DIR/icons/claude-desktop.png" 2>/dev/null || \
    mv "$TARBALL_DIR/icons/"setupIcon_*_256x256*.png "$TARBALL_DIR/icons/claude-desktop.png" 2>/dev/null || true
    # Clean up other sizes
    rm -f "$TARBALL_DIR/icons/setupIcon_"*.png 2>/dev/null || true
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
echo "  Version:      $VERSION"
echo "  Electron:     $ELECTRON_MODE"
echo "  Tarball:      $TARBALL_FILE"
echo "  SHA256:       $SHA256"

# Write metadata file for CI
cat > "$OUTPUT_DIR/build-info.txt" << EOF
VERSION="$VERSION"
TARBALL="$TARBALL_FILE"
SHA256="$SHA256"
ELECTRON_MODE="$ELECTRON_MODE"
EOF
