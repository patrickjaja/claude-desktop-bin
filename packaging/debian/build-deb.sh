#!/bin/bash
#
# Build a Debian package from the pre-patched Claude Desktop tarball.
#
# The tarball (produced by scripts/build-patched-tarball.sh from the official
# Linux .deb) already bundles the Electron runtime under electron/ and the
# patched app under app/. We assemble our own .deb around it; we do NOT download
# or verify a separate Electron zip anymore.
#
# Usage: ./build-deb.sh [--arch amd64|arm64] <tarball_path> <output_dir> [pkgrel]
#
# Requirements: dpkg-deb, tar, fakeroot (recommended)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
if [ "${1:-}" = "--arch" ]; then
    DEB_ARCH="$2"
    shift 2
fi

case "$DEB_ARCH" in
    amd64|arm64) ;;
    *)
        log_error "Unsupported architecture: $DEB_ARCH (supported: amd64, arm64)"
        exit 1
        ;;
esac

# Parse positional arguments
TARBALL_PATH="${1:-}"
OUTPUT_DIR="${2:-}"
PKGREL="${3:-1}"

if [ -z "$TARBALL_PATH" ] || [ -z "$OUTPUT_DIR" ]; then
    echo "Usage: $0 [--arch amd64|arm64] <tarball_path> <output_dir> [pkgrel]"
    echo ""
    echo "Arguments:"
    echo "  --arch        Target architecture (default: amd64, also: arm64)"
    echo "  tarball_path  Path to claude-desktop-VERSION-linux[-aarch64].tar.gz"
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

# Extract version from tarball filename (handles both -linux.tar.gz and -linux-aarch64.tar.gz)
VERSION=$(basename "$TARBALL_PATH" | sed -E 's/claude-desktop-([0-9]+\.[0-9]+\.[0-9]+)-linux(-aarch64)?\.tar\.gz/\1/')
DEB_VERSION="${VERSION}-${PKGREL}"
log_info "Building Debian package for version: $DEB_VERSION (arch: $DEB_ARCH)"

# Create work directory
WORK_DIR=$(mktemp -d)
DEB_ROOT="$WORK_DIR/claude-desktop-bin_${DEB_VERSION}_${DEB_ARCH}"

cleanup() { rm -rf "$WORK_DIR"; }
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

# Install the bundled Electron runtime (from the tarball's electron/ dir)
log_info "Installing bundled Electron runtime..."
cp -r "$WORK_DIR/tarball/electron/"* "$DEB_ROOT/usr/lib/claude-desktop/"

# Rename the Electron binary to "claude". NOTE: this does NOT set the window
# identity. The live X11 WM_CLASS / Wayland app_id is "claude-desktop" (verified
# via xprop/wmctrl), because Chromium's GetXdgAppId() reads the app's desktopName
# ("claude-desktop.desktop" in app.asar package.json), strips ".desktop", and
# ignores the binary basename / --class. The rename is kept only as a cosmetic
# argv[0] / systemd-scope identity hint matching APP_ID="claude". StartupWMClass
# below must equal the real app_id. (The .deb names the binary "claude-desktop".)
if [ -f "$DEB_ROOT/usr/lib/claude-desktop/claude-desktop" ]; then
    mv "$DEB_ROOT/usr/lib/claude-desktop/claude-desktop" "$DEB_ROOT/usr/lib/claude-desktop/claude"
elif [ -f "$DEB_ROOT/usr/lib/claude-desktop/electron" ]; then
    mv "$DEB_ROOT/usr/lib/claude-desktop/electron" "$DEB_ROOT/usr/lib/claude-desktop/claude"
fi

# Set SUID permission on chrome-sandbox (required by Chromium's sandbox)
if [ -f "$DEB_ROOT/usr/lib/claude-desktop/chrome-sandbox" ]; then
    chmod 4755 "$DEB_ROOT/usr/lib/claude-desktop/chrome-sandbox"
    log_info "Set SUID permission on chrome-sandbox"
fi

# Copy application files into Electron's resources directory.
# The tarball ships the app under app/; electron/ has no resources/ subdir
# (only resources.pak), so create resources/ before copying into it.
log_info "Installing application files..."
mkdir -p "$DEB_ROOT/usr/lib/claude-desktop/resources"
cp -r "$WORK_DIR/tarball/app/"* "$DEB_ROOT/usr/lib/claude-desktop/resources/"

# Install launcher (full launcher from tarball with Wayland/X11 detection,
# GPU fallback, SingletonLock cleanup, and logging)
install -m755 "$WORK_DIR/tarball/launcher/claude-desktop" "$DEB_ROOT/usr/bin/claude-desktop"

# Install desktop file.
# Filename is "claude-desktop.desktop" to match the live window app_id
# "claude-desktop" (Chromium's GetXdgAppId() reads the app's desktopName
# "claude-desktop.desktop" from app.asar, strips ".desktop"). On native Wayland
# there is no WM_CLASS, so KWin/GNOME match by app_id; a mismatched basename gives
# a generic icon + Alt+Tab duplicate (issue #148). StartupWMClass fixes X11.
# Content mirrors the official Claude Desktop .deb.
cat > "$DEB_ROOT/usr/share/applications/claude-desktop.desktop" << 'EOF'
[Desktop Entry]
Name=Claude
Comment=Desktop application for Claude.ai
GenericName=AI Assistant
Keywords=AI;Chat;Assistant;Claude;Code;LLM;
Exec=claude-desktop %U
Icon=claude-desktop
Type=Application
StartupNotify=true
StartupWMClass=claude-desktop
# second-instance just focuses mainWindow; suppress GNOME's default "New Window" item
SingleMainWindow=true
Categories=Utility;Development;
MimeType=x-scheme-handler/claude;
Actions=NewChat;NewCode;

[Desktop Action NewChat]
Name=New chat
Exec=claude-desktop claude://claude.ai/new

[Desktop Action NewCode]
Name=New Claude Code session
Exec=claude-desktop claude://code/new
EOF

# Install icon
if [ -f "$WORK_DIR/tarball/icons/claude-desktop.png" ]; then
    cp "$WORK_DIR/tarball/icons/claude-desktop.png" \
        "$DEB_ROOT/usr/share/icons/hicolor/256x256/apps/claude-desktop.png"
fi

# Calculate installed size (in KB)
INSTALLED_SIZE=$(du -sk "$DEB_ROOT" | cut -f1)

# Create control file.
# Depends mirror the official Claude Desktop .deb's runtime needs (Electron 42).
log_info "Creating control file..."
cat > "$DEB_ROOT/DEBIAN/control" << EOF
Package: claude-desktop-bin
Version: ${DEB_VERSION}
Section: utils
Priority: optional
Architecture: ${DEB_ARCH}
Installed-Size: ${INSTALLED_SIZE}
Depends: libgtk-3-0, libnotify4, libnss3, xdg-utils, libatspi2.0-0, libdrm2, libgbm1, libxcb-dri3-0, libsecret-1-0, libc6 (>= 2.34), libxtst6, libuuid1, xdg-desktop-portal
Recommends: libasound2t64 | libasound2 | pulseaudio, libayatana-appindicator3-1 | libappindicator3-1, ca-certificates, sqlite3
Suggests: xdotool, scrot, imagemagick, wmctrl, socat, hyprland, ydotool, grim, jq, kde-spectacle, libglib2.0-bin, python3-gi, gstreamer1.0-pipewire, gnome-screenshot, nodejs, qemu-system-x86, ovmf, qemu-efi-aarch64
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

# postinst: SUID chrome-sandbox + AppArmor userns profile (mirrors the official
# .deb's postinst) + cache refresh. The AppArmor profile is what lets Chromium's
# namespace sandbox work on Ubuntu 24.04+ where unprivileged userns is restricted.
cat > "$DEB_ROOT/DEBIAN/postinst" << 'EOF'
#!/bin/sh
set -e

PROFILE="/etc/apparmor.d/claude-desktop"
BINARY="/usr/lib/claude-desktop/claude"

# chrome-sandbox must be SUID root for Chromium's setuid sandbox.
if [ -f /usr/lib/claude-desktop/chrome-sandbox ]; then
    chown root:root /usr/lib/claude-desktop/chrome-sandbox
    chmod 4755 /usr/lib/claude-desktop/chrome-sandbox
fi

case "$1" in
  configure)
    # AppArmor userns profile (gated on AppArmor 4.0; unparseable/unnecessary on 3.x).
    if [ -f /etc/apparmor.d/abi/4.0 ]; then
        rm -f "$PROFILE"
        cat > "$PROFILE" <<PROF
abi <abi/4.0>,
include <tunables/global>

profile claude-desktop $BINARY flags=(unconfined) {
  userns,

  include if exists <local/claude-desktop>
}
PROF
        chmod 0644 "$PROFILE"
        if command -v aa-enabled >/dev/null 2>&1 && aa-enabled --quiet 2>/dev/null; then
            apparmor_parser -r -W -T "$PROFILE" || true
        fi
    fi
    ;;
esac

if command -v update-icon-caches >/dev/null 2>&1; then
    update-icon-caches /usr/share/icons/hicolor || true
fi
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database /usr/share/applications || true
fi
EOF
chmod +x "$DEB_ROOT/DEBIAN/postinst"

# postrm: remove the AppArmor profile (mirrors the official .deb's postrm) + cache refresh.
cat > "$DEB_ROOT/DEBIAN/postrm" << 'EOF'
#!/bin/sh
set -e

PROFILE="/etc/apparmor.d/claude-desktop"

case "$1" in
  remove|purge)
    if [ -f "$PROFILE" ]; then
        if command -v aa-enabled >/dev/null 2>&1 && aa-enabled --quiet 2>/dev/null; then
            apparmor_parser -R "$PROFILE" || true
        fi
        rm -f "$PROFILE"
    fi
    if command -v update-icon-caches >/dev/null 2>&1; then
        update-icon-caches /usr/share/icons/hicolor || true
    fi
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database /usr/share/applications || true
    fi
    ;;
esac
EOF
chmod +x "$DEB_ROOT/DEBIAN/postrm"

# Build the package
log_info "Building .deb package..."
mkdir -p "$OUTPUT_DIR"
DEB_PATH="$OUTPUT_DIR/claude-desktop-bin_${DEB_VERSION}_${DEB_ARCH}.deb"

if command -v fakeroot >/dev/null 2>&1; then
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
