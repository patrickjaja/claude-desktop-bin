#!/bin/bash
#
# Build a pre-patched tarball from Claude Desktop Windows exe
#
# This script extracts the Windows installer, applies all Linux patches,
# and creates a distributable tarball. The tarball can then be packaged
# for any Linux distribution (Arch, Debian, Snap, Flatpak, etc.)
#
# Usage: ./scripts/build-patched-tarball.sh <exe_path> <output_dir>
#
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PATCHES_DIR="$PROJECT_DIR/patches"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Parse arguments
EXE_PATH="$1"
OUTPUT_DIR="$2"

if [ -z "$EXE_PATH" ] || [ -z "$OUTPUT_DIR" ]; then
    echo "Usage: $0 <exe_path> <output_dir>"
    echo ""
    echo "Arguments:"
    echo "  exe_path    Path to Claude-Setup-x64.exe"
    echo "  output_dir  Directory to write tarball and extracted files"
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

# Apply all patches
log_info "Applying patches..."
PATCH_FAILED=false

for patch_file in "$PATCHES_DIR"/*; do
    [ -f "$patch_file" ] || continue

    filename=$(basename "$patch_file")
    patch_target=$(grep -m1 '@patch-target:' "$patch_file" | sed 's/.*@patch-target:[[:space:]]*//' | tr -d '\r')
    patch_type=$(grep -m1 '@patch-type:' "$patch_file" | sed 's/.*@patch-type:[[:space:]]*//' | tr -d '\r')

    if [ -z "$patch_target" ] || [ -z "$patch_type" ]; then
        log_warn "Skipping $filename - missing @patch-target or @patch-type"
        continue
    fi

    echo "  Applying: $filename"

    case "$patch_type" in
        replace)
            # For replace type, create parent dir and copy file
            target_path="$WORK_DIR/app/$patch_target"
            mkdir -p "$(dirname "$target_path")"
            cp "$patch_file" "$target_path"
            ;;
        python)
            # For python patches, handle glob patterns
            if [[ "$patch_target" == *"*"* ]]; then
                dir_part=$(dirname "$patch_target")
                file_pattern=$(basename "$patch_target")
                target_file=$(find "$WORK_DIR/app/$dir_part" -name "$file_pattern" 2>/dev/null | head -1)
            else
                target_file="$WORK_DIR/app/$patch_target"
            fi

            if [ -z "$target_file" ] || [ ! -f "$target_file" ]; then
                log_error "Target not found for $filename: $patch_target"
                PATCH_FAILED=true
                continue
            fi

            if ! python3 "$patch_file" "$target_file"; then
                log_error "Patch $filename FAILED"
                PATCH_FAILED=true
            fi
            ;;
        *)
            log_warn "Unknown patch type '$patch_type' for $filename"
            ;;
    esac
done

if [ "$PATCH_FAILED" = true ]; then
    log_error "One or more patches failed to apply"
    exit 1
fi

# Repack app.asar
log_info "Repacking app.asar..."
cd "$WORK_DIR/app"
asar pack app.asar.contents app.asar
rm -rf app.asar.contents

# Copy locales
log_info "Copying locales..."
mkdir -p "$WORK_DIR/app/locales"
cp "$WORK_DIR/extract/lib/net45/resources/"*.json "$WORK_DIR/app/locales/" 2>/dev/null || true

# Copy tray icons
log_info "Copying tray icons..."
cp "$WORK_DIR/extract/lib/net45/resources/TrayIconTemplate"*.png "$WORK_DIR/app/locales/" 2>/dev/null || true

# Create tarball structure
log_info "Creating tarball structure..."
TARBALL_DIR="$WORK_DIR/tarball"
mkdir -p "$TARBALL_DIR/app" "$TARBALL_DIR/icons"

# Copy patched app
cp -r "$WORK_DIR/app"/* "$TARBALL_DIR/app/"

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
tar -czvf "$TARBALL_FILE" app/ icons/

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
VERSION=$VERSION
TARBALL=$TARBALL_FILE
SHA256=$SHA256
EOF
