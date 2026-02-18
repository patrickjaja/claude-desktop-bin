#!/bin/bash
#
# Build Debian package from pre-patched Claude Desktop tarball
#
# Usage: ./build-deb.sh <tarball_path> <output_dir>
#
# Requirements: dpkg-deb, fakeroot (optional but recommended)
#
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
    echo "  output_dir    Directory to write .deb package"
    echo ""
    echo "Output:"
    echo "  <output_dir>/claude-desktop-bin_<version>_amd64.deb"
    exit 1
fi

if [ ! -f "$TARBALL_PATH" ]; then
    log_error "Tarball not found: $TARBALL_PATH"
    exit 1
fi

# Extract version from tarball filename
VERSION=$(basename "$TARBALL_PATH" | sed -E 's/claude-desktop-([0-9]+\.[0-9]+\.[0-9]+)-linux\.tar\.gz/\1/')
log_info "Building Debian package for version: $VERSION"

# Create work directory
WORK_DIR=$(mktemp -d)
DEB_ROOT="$WORK_DIR/claude-desktop-bin_${VERSION}_amd64"

cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

# Extract tarball
log_info "Extracting Claude Desktop tarball..."
mkdir -p "$WORK_DIR/tarball"
tar -xzf "$TARBALL_PATH" -C "$WORK_DIR/tarball"

# Create directory structure
log_info "Creating package structure..."
mkdir -p "$DEB_ROOT/DEBIAN"
mkdir -p "$DEB_ROOT/usr/lib/claude-desktop"
mkdir -p "$DEB_ROOT/usr/bin"
mkdir -p "$DEB_ROOT/usr/share/applications"
mkdir -p "$DEB_ROOT/usr/share/icons/hicolor/256x256/apps"

# Copy application files
log_info "Installing application files..."
cp -r "$WORK_DIR/tarball/app/"* "$DEB_ROOT/usr/lib/claude-desktop/"

# Install launcher script
cat > "$DEB_ROOT/usr/bin/claude-desktop" << 'EOF'
#!/bin/bash
exec electron /usr/lib/claude-desktop/app.asar "$@"
EOF
chmod +x "$DEB_ROOT/usr/bin/claude-desktop"

# Install desktop file
cat > "$DEB_ROOT/usr/share/applications/claude-desktop.desktop" << EOF
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
EOF

# Install icon
if [ -f "$WORK_DIR/tarball/icons/claude-desktop.png" ]; then
    cp "$WORK_DIR/tarball/icons/claude-desktop.png" \
        "$DEB_ROOT/usr/share/icons/hicolor/256x256/apps/claude-desktop.png"
fi

# Calculate installed size (in KB)
INSTALLED_SIZE=$(du -sk "$DEB_ROOT" | cut -f1)

# Create control file
log_info "Creating control file..."
cat > "$DEB_ROOT/DEBIAN/control" << EOF
Package: claude-desktop-bin
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: amd64
Installed-Size: ${INSTALLED_SIZE}
Depends: electron | electron-bin | electron33
Recommends: libnotify-bin
Maintainer: Claude Desktop Linux Community <claude-desktop-linux@users.noreply.github.com>
Homepage: https://claude.ai
Description: Claude AI Desktop Application
 Claude is an AI assistant created by Anthropic to be helpful,
 harmless, and honest. This desktop application provides native
 access to Claude with features including conversational AI,
 code generation, document understanding, and system tray integration.
 .
 Note: This is an unofficial Linux port. Requires an Anthropic account.
EOF

# Create postinst script for icon cache update
cat > "$DEB_ROOT/DEBIAN/postinst" << 'EOF'
#!/bin/bash
set -e
if command -v update-icon-caches &> /dev/null; then
    update-icon-caches /usr/share/icons/hicolor || true
fi
if command -v update-desktop-database &> /dev/null; then
    update-desktop-database /usr/share/applications || true
fi
EOF
chmod +x "$DEB_ROOT/DEBIAN/postinst"

# Create postrm script
cat > "$DEB_ROOT/DEBIAN/postrm" << 'EOF'
#!/bin/bash
set -e
if [ "$1" = "remove" ] || [ "$1" = "purge" ]; then
    if command -v update-icon-caches &> /dev/null; then
        update-icon-caches /usr/share/icons/hicolor || true
    fi
    if command -v update-desktop-database &> /dev/null; then
        update-desktop-database /usr/share/applications || true
    fi
fi
EOF
chmod +x "$DEB_ROOT/DEBIAN/postrm"

# Build the package
log_info "Building .deb package..."
mkdir -p "$OUTPUT_DIR"
DEB_PATH="$OUTPUT_DIR/claude-desktop-bin_${VERSION}_amd64.deb"

if command -v fakeroot &> /dev/null; then
    fakeroot dpkg-deb --build "$DEB_ROOT" "$DEB_PATH"
else
    dpkg-deb --build "$DEB_ROOT" "$DEB_PATH"
fi

# Calculate SHA256
SHA256=$(sha256sum "$DEB_PATH" | cut -d' ' -f1)

log_info "Debian package built successfully!"
echo "  Version:  $VERSION"
echo "  Path:     $DEB_PATH"
echo "  SHA256:   $SHA256"

# Write build info
cat > "$OUTPUT_DIR/deb-info.txt" << EOF
VERSION=$VERSION
DEB=$DEB_PATH
SHA256=$SHA256
EOF
