#!/bin/bash
#
# Local build script for claude-desktop-bin
#
# This script downloads the latest Claude Desktop for Windows,
# generates a PKGBUILD, and builds the Arch Linux package locally.
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
            exit 0
            ;;
    esac
done

# Check dependencies
log_info "Checking build dependencies..."
MISSING_DEPS=()
for dep in wget 7z makepkg asar python3; do
    if ! command -v "$dep" &> /dev/null; then
        MISSING_DEPS+=("$dep")
    fi
done

if [ ${#MISSING_DEPS[@]} -ne 0 ]; then
    log_error "Missing dependencies: ${MISSING_DEPS[*]}"
    echo "Install them with: sudo pacman -S p7zip wget base-devel python"
    echo "For asar: npm install -g asar"
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
    # Download the latest Claude Desktop
    DOWNLOAD_URL="https://downloads.claude.ai/releases/win32/x64/latest/Claude-Setup-x64.exe"

    log_info "Downloading Claude Desktop for Windows..."
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

# Extract version
log_info "Extracting version information..."
VERSION=$("$SCRIPT_DIR/extract-version.sh" "$EXE_FILE")
log_info "Detected version: $VERSION"

# Calculate SHA256
log_info "Calculating SHA256 checksum..."
SHA256SUM=$(sha256sum "$EXE_FILE" | cut -d' ' -f1)
log_info "SHA256: $SHA256SUM"

# Rename exe to include version (makepkg expects this)
VERSIONED_EXE="$BUILD_DIR/Claude-Setup-x64-${VERSION}.exe"
mv "$EXE_FILE" "$VERSIONED_EXE"

# Generate PKGBUILD
log_info "Generating PKGBUILD..."
"$SCRIPT_DIR/generate-pkgbuild.sh" "$VERSION" "$SHA256SUM" "file://$VERSIONED_EXE" > "$BUILD_DIR/PKGBUILD"

# Copy patches directory
log_info "Copying patches..."
cp -r "$PROJECT_DIR/patches" "$BUILD_DIR/"

# Build the package
log_info "Building package with makepkg..."
cd "$BUILD_DIR"

# -s: install missing dependencies
# -f: force rebuild if package exists
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
