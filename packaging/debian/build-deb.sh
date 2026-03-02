#!/bin/bash
#
# Build Debian package from pre-patched Claude Desktop tarball
#
# Usage: ./build-deb.sh <tarball_path> <output_dir>
#
# Requirements: dpkg-deb, wget, unzip, fakeroot (optional but recommended)
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
PKGREL="${3:-1}"

if [ -z "$TARBALL_PATH" ] || [ -z "$OUTPUT_DIR" ]; then
    echo "Usage: $0 <tarball_path> <output_dir> [pkgrel]"
    echo ""
    echo "Arguments:"
    echo "  tarball_path  Path to claude-desktop-VERSION-linux.tar.gz"
    echo "  output_dir    Directory to write .deb package"
    echo "  pkgrel        Package release number (default: 1)"
    echo ""
    echo "Output:"
    echo "  <output_dir>/claude-desktop-bin_<version>-<pkgrel>_amd64.deb"
    exit 1
fi

if [ ! -f "$TARBALL_PATH" ]; then
    log_error "Tarball not found: $TARBALL_PATH"
    exit 1
fi

# Extract version from tarball filename
VERSION=$(basename "$TARBALL_PATH" | sed -E 's/claude-desktop-([0-9]+\.[0-9]+\.[0-9]+)-linux\.tar\.gz/\1/')
DEB_VERSION="${VERSION}-${PKGREL}"
log_info "Building Debian package for version: $DEB_VERSION"

# Create work directory
WORK_DIR=$(mktemp -d)
DEB_ROOT="$WORK_DIR/claude-desktop-bin_${DEB_VERSION}_amd64"

cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

# Extract tarball
log_info "Extracting Claude Desktop tarball..."
mkdir -p "$WORK_DIR/tarball"
tar -xzf "$TARBALL_PATH" -C "$WORK_DIR/tarball"

# Download Electron
log_info "Downloading Electron v${ELECTRON_VERSION}..."
ELECTRON_ZIP="$WORK_DIR/electron.zip"
wget -q -O "$ELECTRON_ZIP" \
    "https://github.com/electron/electron/releases/download/v${ELECTRON_VERSION}/electron-v${ELECTRON_VERSION}-linux-x64.zip"

# Create directory structure
log_info "Creating package structure..."
mkdir -p "$DEB_ROOT/DEBIAN"
mkdir -p "$DEB_ROOT/usr/lib/claude-desktop"
mkdir -p "$DEB_ROOT/usr/bin"
mkdir -p "$DEB_ROOT/usr/share/applications"
mkdir -p "$DEB_ROOT/usr/share/icons/hicolor/256x256/apps"

# Extract Electron
log_info "Extracting Electron..."
unzip -q "$ELECTRON_ZIP" -d "$DEB_ROOT/usr/lib/claude-desktop"

# Set SUID permission on chrome-sandbox (required by Chromium's sandbox)
if [ -f "$DEB_ROOT/usr/lib/claude-desktop/chrome-sandbox" ]; then
    chmod 4755 "$DEB_ROOT/usr/lib/claude-desktop/chrome-sandbox"
    log_info "Set SUID permission on chrome-sandbox"
fi

# Copy application files into Electron's resources directory
log_info "Installing application files..."
cp -r "$WORK_DIR/tarball/app/"* "$DEB_ROOT/usr/lib/claude-desktop/resources/"

# Install launcher script
cat > "$DEB_ROOT/usr/bin/claude-desktop" << 'EOF'
#!/bin/bash
export ELECTRON_OZONE_PLATFORM_HINT="${ELECTRON_OZONE_PLATFORM_HINT:-auto}"
exec /usr/lib/claude-desktop/electron /usr/lib/claude-desktop/resources/app.asar "$@"
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
Version: ${DEB_VERSION}
Section: utils
Priority: optional
Architecture: amd64
Installed-Size: ${INSTALLED_SIZE}
Depends: libgtk-3-0, libnotify4, libnss3, libxss1, libxtst6, libatspi2.0-0, libdrm2, libgbm1, libasound2
Recommends: libnotify-bin
Suggests: nodejs, npm
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

# Create postinst script for sandbox permissions and icon cache update
cat > "$DEB_ROOT/DEBIAN/postinst" << 'EOF'
#!/bin/bash
set -e
# Ensure chrome-sandbox has SUID root (required by Chromium's setuid sandbox)
if [ -f /usr/lib/claude-desktop/chrome-sandbox ]; then
    chown root:root /usr/lib/claude-desktop/chrome-sandbox
    chmod 4755 /usr/lib/claude-desktop/chrome-sandbox
fi
if command -v update-icon-caches &> /dev/null; then
    update-icon-caches /usr/share/icons/hicolor || true
fi
if command -v update-desktop-database &> /dev/null; then
    update-desktop-database /usr/share/applications || true
fi

# Show optional dependency hints
if [ "$1" = "configure" ]; then
    echo ""
    echo "Optional dependencies for claude-desktop-bin:"
    echo "  claude-code: Claude Code CLI for agentic coding features (npm i -g @anthropic-ai/claude-code)"
    echo ""
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
DEB_PATH="$OUTPUT_DIR/claude-desktop-bin_${DEB_VERSION}_amd64.deb"

if command -v fakeroot &> /dev/null; then
    fakeroot dpkg-deb --build "$DEB_ROOT" "$DEB_PATH"
else
    dpkg-deb --build "$DEB_ROOT" "$DEB_PATH"
fi

# Calculate SHA256
SHA256=$(sha256sum "$DEB_PATH" | cut -d' ' -f1)

log_info "Debian package built successfully!"
echo "  Version:  $DEB_VERSION"
echo "  Path:     $DEB_PATH"
echo "  SHA256:   $SHA256"

# Write build info
cat > "$OUTPUT_DIR/deb-info.txt" << EOF
VERSION=$DEB_VERSION
DEB=$DEB_PATH
SHA256=$SHA256
EOF
