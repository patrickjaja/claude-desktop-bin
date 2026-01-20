#!/bin/bash
#
# Build AppImage from pre-patched Claude Desktop tarball
#
# Usage: ./build-appimage.sh <tarball_path> <output_dir>
#
# Requirements: wget, appimagetool (or will be downloaded)
#
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Electron version to bundle (can be overridden via environment variable)
# If not set, fetches latest stable from GitHub
if [ -z "$ELECTRON_VERSION" ]; then
    ELECTRON_VERSION=$(curl -s https://api.github.com/repos/electron/electron/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
    if [ -z "$ELECTRON_VERSION" ]; then
        echo "Failed to fetch latest Electron version, using fallback"
        ELECTRON_VERSION="33.2.1"
    fi
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Parse arguments
TARBALL_PATH="$1"
OUTPUT_DIR="$2"

if [ -z "$TARBALL_PATH" ] || [ -z "$OUTPUT_DIR" ]; then
    echo "Usage: $0 <tarball_path> <output_dir>"
    echo ""
    echo "Arguments:"
    echo "  tarball_path  Path to claude-desktop-VERSION-linux.tar.gz"
    echo "  output_dir    Directory to write AppImage"
    echo ""
    echo "Output:"
    echo "  <output_dir>/Claude_Desktop-<version>-x86_64.AppImage"
    exit 1
fi

if [ ! -f "$TARBALL_PATH" ]; then
    log_error "Tarball not found: $TARBALL_PATH"
    exit 1
fi

# Extract version from tarball filename
VERSION=$(basename "$TARBALL_PATH" | sed -E 's/claude-desktop-([0-9]+\.[0-9]+\.[0-9]+)-linux\.tar\.gz/\1/')
log_info "Building AppImage for version: $VERSION"

# Create work directory
WORK_DIR=$(mktemp -d)
APPDIR="$WORK_DIR/Claude_Desktop.AppDir"
mkdir -p "$APPDIR"

cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

# Download appimagetool if not available
if ! command -v appimagetool &> /dev/null; then
    log_info "Downloading appimagetool..."
    APPIMAGETOOL="$WORK_DIR/appimagetool"
    wget -q -O "$APPIMAGETOOL" \
        "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"
    chmod +x "$APPIMAGETOOL"
else
    APPIMAGETOOL="appimagetool"
fi

# Download Electron
log_info "Downloading Electron v${ELECTRON_VERSION}..."
ELECTRON_ZIP="$WORK_DIR/electron.zip"
wget -q -O "$ELECTRON_ZIP" \
    "https://github.com/electron/electron/releases/download/v${ELECTRON_VERSION}/electron-v${ELECTRON_VERSION}-linux-x64.zip"

# Extract Electron to AppDir
log_info "Extracting Electron..."
unzip -q "$ELECTRON_ZIP" -d "$APPDIR/usr/lib/claude-desktop"

# Extract tarball
log_info "Extracting Claude Desktop tarball..."
tar -xzf "$TARBALL_PATH" -C "$WORK_DIR/tarball" --strip-components=0 || \
    (mkdir -p "$WORK_DIR/tarball" && tar -xzf "$TARBALL_PATH" -C "$WORK_DIR/tarball")

# Copy app files to Electron resources directory
log_info "Installing application files..."
mkdir -p "$APPDIR/usr/lib/claude-desktop/resources"
cp -r "$WORK_DIR/tarball/app/"* "$APPDIR/usr/lib/claude-desktop/resources/"

# Rename electron binary to claude-desktop
mv "$APPDIR/usr/lib/claude-desktop/electron" "$APPDIR/usr/lib/claude-desktop/claude-desktop"

# Create AppRun
log_info "Creating AppRun..."
cat > "$APPDIR/AppRun" << 'EOF'
#!/bin/bash
SELF=$(readlink -f "$0")
HERE=${SELF%/*}
export PATH="${HERE}/usr/bin:${PATH}"
export LD_LIBRARY_PATH="${HERE}/usr/lib/claude-desktop:${LD_LIBRARY_PATH}"
export ELECTRON_OZONE_PLATFORM_HINT="${ELECTRON_OZONE_PLATFORM_HINT:-auto}"
exec "${HERE}/usr/lib/claude-desktop/claude-desktop" "${HERE}/usr/lib/claude-desktop/resources/app.asar" "$@"
EOF
chmod +x "$APPDIR/AppRun"

# Create desktop file
log_info "Creating desktop file..."
mkdir -p "$APPDIR/usr/share/applications"
cat > "$APPDIR/claude-desktop.desktop" << EOF
[Desktop Entry]
Name=Claude
Comment=Claude AI Desktop Application
Exec=claude-desktop %u
Icon=claude-desktop
Type=Application
Terminal=false
Categories=Office;Utility;Chat;
MimeType=x-scheme-handler/claude;
StartupWMClass=Claude
X-AppImage-Version=${VERSION}
EOF
cp "$APPDIR/claude-desktop.desktop" "$APPDIR/usr/share/applications/"

# Copy icon
log_info "Installing icon..."
if [ -f "$WORK_DIR/tarball/icons/claude-desktop.png" ]; then
    cp "$WORK_DIR/tarball/icons/claude-desktop.png" "$APPDIR/claude-desktop.png"
    mkdir -p "$APPDIR/usr/share/icons/hicolor/256x256/apps"
    cp "$WORK_DIR/tarball/icons/claude-desktop.png" "$APPDIR/usr/share/icons/hicolor/256x256/apps/"
else
    log_warn "Icon not found in tarball"
fi

# Create .DirIcon symlink
if [ -f "$APPDIR/claude-desktop.png" ]; then
    ln -sf claude-desktop.png "$APPDIR/.DirIcon"
fi

# Build AppImage
log_info "Building AppImage..."
mkdir -p "$OUTPUT_DIR"
APPIMAGE_PATH="$OUTPUT_DIR/Claude_Desktop-${VERSION}-x86_64.AppImage"

# Set architecture for appimagetool
export ARCH=x86_64

"$APPIMAGETOOL" "$APPDIR" "$APPIMAGE_PATH"

# Calculate SHA256
SHA256=$(sha256sum "$APPIMAGE_PATH" | cut -d' ' -f1)

log_info "AppImage built successfully!"
echo "  Version:  $VERSION"
echo "  Path:     $APPIMAGE_PATH"
echo "  SHA256:   $SHA256"

# Write build info
cat > "$OUTPUT_DIR/appimage-info.txt" << EOF
VERSION=$VERSION
APPIMAGE=$APPIMAGE_PATH
SHA256=$SHA256
EOF
