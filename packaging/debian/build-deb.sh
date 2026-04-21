#!/bin/bash
#
# Build Debian package from pre-patched Claude Desktop tarball
#
# Usage: ./build-deb.sh [--arch amd64|arm64] <tarball_path> <output_dir> [pkgrel]
#
# Requirements: dpkg-deb, wget, unzip, fakeroot (optional but recommended)
#
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Fetch latest stable Electron version from GitHub (unless overridden via env)
if [ -z "$ELECTRON_VERSION" ]; then
    ELECTRON_VERSION=$(curl -sf https://api.github.com/repos/electron/electron/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/' || true)
    if [ -z "$ELECTRON_VERSION" ]; then
        echo "Error: Could not fetch latest Electron version from GitHub API." >&2
        exit 1
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

# Parse optional --arch flag (default: amd64)
DEB_ARCH="amd64"
if [ "$1" = "--arch" ]; then
    DEB_ARCH="$2"
    shift 2
fi

# Map Debian arch to Electron arch
case "$DEB_ARCH" in
    amd64)  ELECTRON_ARCH="x64" ;;
    arm64)  ELECTRON_ARCH="arm64" ;;
    *)
        log_error "Unsupported architecture: $DEB_ARCH (supported: amd64, arm64)"
        exit 1
        ;;
esac

# Parse positional arguments
TARBALL_PATH="$1"
OUTPUT_DIR="$2"
PKGREL="${3:-1}"

if [ -z "$TARBALL_PATH" ] || [ -z "$OUTPUT_DIR" ]; then
    echo "Usage: $0 [--arch amd64|arm64] <tarball_path> <output_dir> [pkgrel]"
    echo ""
    echo "Arguments:"
    echo "  --arch        Target architecture (default: amd64, also: arm64)"
    echo "  tarball_path  Path to claude-desktop-VERSION-linux.tar.gz"
    echo "  output_dir    Directory to write .deb package"
    echo "  pkgrel        Package release number (default: 1)"
    echo ""
    echo "Output:"
    echo "  <output_dir>/claude-desktop-bin_<version>-<pkgrel>_<arch>.deb"
    exit 1
fi

if [ ! -f "$TARBALL_PATH" ]; then
    log_error "Tarball not found: $TARBALL_PATH"
    exit 1
fi

# Extract version from tarball filename
VERSION=$(basename "$TARBALL_PATH" | sed -E 's/claude-desktop-([0-9]+\.[0-9]+\.[0-9]+)-linux\.tar\.gz/\1/')
DEB_VERSION="${VERSION}-${PKGREL}"
log_info "Building Debian package for version: $DEB_VERSION (arch: $DEB_ARCH, electron: $ELECTRON_ARCH)"

# Create work directory
WORK_DIR=$(mktemp -d)
DEB_ROOT="$WORK_DIR/claude-desktop-bin_${DEB_VERSION}_${DEB_ARCH}"

cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

# Extract tarball
log_info "Extracting Claude Desktop tarball..."
mkdir -p "$WORK_DIR/tarball"
tar -xzf "$TARBALL_PATH" -C "$WORK_DIR/tarball"

# Download Electron
log_info "Downloading Electron v${ELECTRON_VERSION} for ${ELECTRON_ARCH}..."
ELECTRON_ZIP="$WORK_DIR/electron.zip"
wget -q -O "$ELECTRON_ZIP" \
    "https://github.com/electron/electron/releases/download/v${ELECTRON_VERSION}/electron-v${ELECTRON_VERSION}-linux-${ELECTRON_ARCH}.zip"

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

# Rename the Electron binary to APP_ID. Electron ignores Chromium's --class
# flag and derives Wayland app_id / X11 WM_CLASS from the binary basename.
# The name must match .desktop filename + StartupWMClass so xdg-desktop-portal
# (and window-manager icon binding) can resolve us via app_id.
mv "$DEB_ROOT/usr/lib/claude-desktop/electron" \
   "$DEB_ROOT/usr/lib/claude-desktop/com.anthropic.claude-desktop"

# Set SUID permission on chrome-sandbox (required by Chromium's sandbox)
if [ -f "$DEB_ROOT/usr/lib/claude-desktop/chrome-sandbox" ]; then
    chmod 4755 "$DEB_ROOT/usr/lib/claude-desktop/chrome-sandbox"
    log_info "Set SUID permission on chrome-sandbox"
fi

# Copy application files into Electron's resources directory
log_info "Installing application files..."
cp -r "$WORK_DIR/tarball/app/"* "$DEB_ROOT/usr/lib/claude-desktop/resources/"

# Install launcher (full launcher from tarball with Wayland/X11 detection,
# GPU fallback, SingletonLock cleanup, cowork socket cleanup, and logging)
install -m755 "$WORK_DIR/tarball/launcher/claude-desktop" "$DEB_ROOT/usr/bin/claude-desktop"

# Install desktop file.
# Filename must match APP_ID in the launcher (com.anthropic.claude-desktop)
# so xdg-desktop-portal can resolve our systemd-scope / cgroup identity.
cat > "$DEB_ROOT/usr/share/applications/com.anthropic.claude-desktop.desktop" << EOF
[Desktop Entry]
Name=Claude
Comment=Claude AI Desktop Application
Exec=claude-desktop %u
Icon=claude-desktop
Type=Application
Terminal=false
Categories=Office;Utility;Chat;
MimeType=x-scheme-handler/claude;
StartupWMClass=com.anthropic.claude-desktop
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
Architecture: ${DEB_ARCH}
Installed-Size: ${INSTALLED_SIZE}
Depends: libgtk-3-0, libnotify4, libnss3, libxss1, libxtst6, libatspi2.0-0, libdrm2, libgbm1, libasound2
Recommends: libnotify-bin
Suggests: xdotool, scrot, imagemagick, wmctrl, socat, hyprland, ydotool, grim, jq, kde-spectacle, libglib2.0-bin, gnome-screenshot, nodejs
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
DEB_PATH="$OUTPUT_DIR/claude-desktop-bin_${DEB_VERSION}_${DEB_ARCH}.deb"

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
VERSION="$DEB_VERSION"
DEB="$DEB_PATH"
SHA256="$SHA256"
EOF
