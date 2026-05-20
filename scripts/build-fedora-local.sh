#!/bin/bash
#
# Local build script for Fedora — builds an installable RPM from source
#
# This script downloads the latest Claude Desktop for Windows,
# applies Linux patches, and builds an RPM package for Fedora.
#
# Usage: ./scripts/build-fedora-local.sh [--install]
#
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Parse arguments
INSTALL_AFTER_BUILD=false
SKIP_SMOKE_TEST="${SKIP_SMOKE_TEST:-1}"
for arg in "$@"; do
    case $arg in
        --install|-i)
            INSTALL_AFTER_BUILD=true
            shift
            ;;
        --smoke-test)
            SKIP_SMOKE_TEST=0
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --install, -i    Install the RPM after building"
            echo "  --smoke-test     Run Electron smoke test (skipped by default)"
            echo "  --help, -h       Show this help message"
            echo ""
            echo "This script:"
            echo "  1. Downloads Claude Desktop for Windows (if not present)"
            echo "  2. Applies Linux patches using build-patched-tarball.sh"
            echo "  3. Builds an RPM package using packaging/rpm/build-rpm.sh"
            echo "  4. Optionally installs it with dnf"
            exit 0
            ;;
    esac
done

# Check dependencies
log_info "Checking build dependencies..."
MISSING_DEPS=()
for dep in wget 7z asar python3 rpmbuild unzip; do
    if ! command -v "$dep" &> /dev/null; then
        MISSING_DEPS+=("$dep")
    fi
done

if [ ${#MISSING_DEPS[@]} -ne 0 ]; then
    log_error "Missing dependencies: ${MISSING_DEPS[*]}"
    echo "Install them with:"
    echo "  sudo dnf install p7zip wget rpm-build unzip ImageMagick"
    echo "  npm install -g @electron/asar  (if asar is missing)"
    exit 1
fi

# Create build directory
log_info "Setting up build directory..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Download latest msix (same logic as build-local.sh)
MSIX_FILE="$BUILD_DIR/Claude.msix"
LOCAL_MSIX="$PROJECT_DIR/Claude.msix"

log_info "Querying Claude Desktop version API..."
LATEST_JSON=$(wget -q -O - "https://downloads.claude.ai/releases/win32/x64/.latest")
if [ -z "$LATEST_JSON" ]; then
    log_error "Failed to query version API"
    exit 1
fi
LATEST_VERSION=$(echo "$LATEST_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['version'])")
LATEST_HASH=$(echo "$LATEST_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['hash'])")
DOWNLOAD_URL="https://downloads.claude.ai/releases/win32/x64/${LATEST_VERSION}/Claude-${LATEST_HASH}.msix"

if [ -f "$LOCAL_MSIX" ]; then
    LOCAL_VERSION=$("$SCRIPT_DIR/extract-version.sh" "$LOCAL_MSIX" 2>/dev/null || echo "unknown")
    if [ "$LOCAL_VERSION" = "$LATEST_VERSION" ]; then
        log_info "Local msix is already latest (v$LATEST_VERSION), reusing"
        cp "$LOCAL_MSIX" "$MSIX_FILE"
    else
        log_info "Local msix is v$LOCAL_VERSION, latest is v$LATEST_VERSION — downloading update"
        wget -O "$MSIX_FILE" \
            -U "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
            "$DOWNLOAD_URL" 2>&1

        if [ ! -f "$MSIX_FILE" ] || [ ! -s "$MSIX_FILE" ]; then
            log_error "Download failed."
            log_info "You can manually download from: https://claude.ai/download"
            log_info "Then place the msix in $PROJECT_DIR/Claude.msix and re-run"
            exit 1
        fi
        cp "$MSIX_FILE" "$LOCAL_MSIX"
        log_info "Download complete, local msix updated"
    fi
else
    log_info "Downloading Claude Desktop for Windows (msix)..."
    log_info "Latest version: $LATEST_VERSION"
    log_info "Download URL: $DOWNLOAD_URL"

    wget -O "$MSIX_FILE" \
        -U "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
        "$DOWNLOAD_URL" 2>&1

    if [ ! -f "$MSIX_FILE" ] || [ ! -s "$MSIX_FILE" ]; then
        log_error "Download failed."
        log_info "You can manually download from: https://claude.ai/download"
        log_info "Then place the msix in $PROJECT_DIR/Claude.msix and re-run"
        exit 1
    fi
    cp "$MSIX_FILE" "$LOCAL_MSIX"
    log_info "Download complete"
fi

# Build the patched tarball (shared with all distros)
log_info "Building patched tarball..."
SKIP_SMOKE_TEST="$SKIP_SMOKE_TEST" "$SCRIPT_DIR/build-patched-tarball.sh" "$MSIX_FILE" "$BUILD_DIR"

# Read build info
source "$BUILD_DIR/build-info.txt"
log_info "Built version: $VERSION"
log_info "Tarball: $TARBALL"

# Build RPM using existing packaging script
log_info "Building RPM package..."
RPM_OUTPUT="$BUILD_DIR/rpm"
mkdir -p "$RPM_OUTPUT"
"$PROJECT_DIR/packaging/rpm/build-rpm.sh" "$TARBALL" "$RPM_OUTPUT"

# Find the built RPM
RPM_FILE=$(find "$RPM_OUTPUT" -name "*.rpm" -type f | head -1)

if [ -z "$RPM_FILE" ]; then
    log_error "Build failed - no RPM file found"
    exit 1
fi

# Copy RPM to build dir for easy access
cp "$RPM_FILE" "$BUILD_DIR/"
RPM_FILE="$BUILD_DIR/$(basename "$RPM_FILE")"

log_info "RPM built successfully: $RPM_FILE"

# Install if requested
if [ "$INSTALL_AFTER_BUILD" = true ]; then
    log_info "Installing RPM..."
    sudo dnf install -y "$RPM_FILE"
    log_info "Installation complete! Run 'claude-desktop' to start."
else
    echo ""
    log_info "To install the RPM, run:"
    echo "  sudo dnf install $RPM_FILE"
fi

echo ""
log_info "Build complete!"
