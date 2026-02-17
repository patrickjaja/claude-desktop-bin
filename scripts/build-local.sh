#!/bin/bash
#
# Local build script for claude-desktop-bin
#
# This script downloads the latest Claude Desktop for Windows,
# builds a pre-patched tarball, and optionally installs using pacman.
#
# Usage: ./scripts/build-local.sh [--install]
#
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Parse arguments
INSTALL_AFTER_BUILD=false
for arg in "$@"; do
    case $arg in
        --install|-i)
            INSTALL_AFTER_BUILD=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --install, -i    Install the package after building"
            echo "  --help, -h       Show this help message"
            echo ""
            echo "This script:"
            echo "  1. Downloads Claude Desktop for Windows (if not present)"
            echo "  2. Applies Linux patches using build-patched-tarball.sh"
            echo "  3. Creates a .pkg.tar.zst package"
            echo "  4. Optionally installs it"
            exit 0
            ;;
    esac
done

# Check dependencies
log_info "Checking build dependencies..."
MISSING_DEPS=()
for dep in wget 7z asar python3 icotool makepkg; do
    if ! command -v "$dep" &> /dev/null; then
        MISSING_DEPS+=("$dep")
    fi
done

if [ ${#MISSING_DEPS[@]} -ne 0 ]; then
    log_error "Missing dependencies: ${MISSING_DEPS[*]}"
    echo "Install them with: sudo pacman -S p7zip wget base-devel python icoutils"
    echo "For asar: yay -S asar (or npm install -g @electron/asar)"
    exit 1
fi

# Create build directory
log_info "Setting up build directory..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Check for existing exe in project directory first
EXE_FILE="$BUILD_DIR/Claude-Setup-x64.exe"
LOCAL_EXE="$PROJECT_DIR/Claude-Setup-x64.exe"

if [ -f "$LOCAL_EXE" ]; then
    log_info "Using existing exe: $LOCAL_EXE"
    cp "$LOCAL_EXE" "$EXE_FILE"
else
    # Query version API for latest version and hash
    log_info "Querying Claude Desktop version API..."
    LATEST_JSON=$(wget -q -O - "https://downloads.claude.ai/releases/win32/x64/.latest")
    if [ -z "$LATEST_JSON" ]; then
        log_error "Failed to query version API"
        exit 1
    fi
    LATEST_VERSION=$(echo "$LATEST_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['version'])")
    LATEST_HASH=$(echo "$LATEST_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['hash'])")
    DOWNLOAD_URL="https://downloads.claude.ai/releases/win32/x64/${LATEST_VERSION}/Claude-${LATEST_HASH}.exe"

    log_info "Downloading Claude Desktop for Windows..."
    log_info "Latest version: $LATEST_VERSION"
    log_info "Download URL: $DOWNLOAD_URL"

    wget -O "$EXE_FILE" \
        -U "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
        "$DOWNLOAD_URL" 2>&1

    if [ ! -f "$EXE_FILE" ] || [ ! -s "$EXE_FILE" ]; then
        log_error "Download failed."
        log_info "You can manually download from: https://claude.ai/download"
        log_info "Then place the exe in $PROJECT_DIR/Claude-Setup-x64.exe and re-run"
        exit 1
    fi

    log_info "Download complete"
fi

# Build the patched tarball
log_info "Building patched tarball..."
"$SCRIPT_DIR/build-patched-tarball.sh" "$EXE_FILE" "$BUILD_DIR"

# Read build info
source "$BUILD_DIR/build-info.txt"
log_info "Built version: $VERSION"
log_info "Tarball: $TARBALL"
log_info "SHA256: $SHA256"

# Generate PKGBUILD
log_info "Generating PKGBUILD..."
"$SCRIPT_DIR/generate-pkgbuild.sh" "$VERSION" "$SHA256" "file://$TARBALL" > "$BUILD_DIR/PKGBUILD"

# Build the package with makepkg
log_info "Building Arch package..."
cd "$BUILD_DIR"
makepkg -sf --noconfirm

# Find the built package
PKG_FILE=$(ls claude-desktop-bin-*.pkg.tar.zst 2>/dev/null | head -1)

if [ -z "$PKG_FILE" ]; then
    log_error "Build failed - no package file found"
    exit 1
fi

log_info "Package built successfully: $BUILD_DIR/$PKG_FILE"

# Install if requested
if [ "$INSTALL_AFTER_BUILD" = true ]; then
    log_info "Installing package..."
    sudo pacman -U --noconfirm "$BUILD_DIR/$PKG_FILE"
    log_info "Installation complete! Run 'claude-desktop' to start."
else
    echo ""
    log_info "To install the package, run:"
    echo "  sudo pacman -U $BUILD_DIR/$PKG_FILE"
fi

echo ""
log_info "Build complete!"
