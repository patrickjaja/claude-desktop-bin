#!/bin/bash
#
# Build RPM package from pre-patched Claude Desktop tarball
#
# Usage: ./build-rpm.sh <tarball_path> <output_dir>
#
# Requirements: rpmbuild, wget, unzip
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Electron version to bundle (can be overridden via environment variable)
if [ -z "${ELECTRON_VERSION:-}" ]; then
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
    echo "  output_dir    Directory to write .rpm package"
    echo ""
    echo "Output:"
    echo "  <output_dir>/claude-desktop-bin-<version>-1.x86_64.rpm"
    exit 1
fi

if [ ! -f "$TARBALL_PATH" ]; then
    log_error "Tarball not found: $TARBALL_PATH"
    exit 1
fi

# Extract version from tarball filename
VERSION=$(basename "$TARBALL_PATH" | sed -E 's/claude-desktop-([0-9]+\.[0-9]+\.[0-9]+)-linux\.tar\.gz/\1/')
log_info "Building RPM package for version: $VERSION"

# Create rpmbuild directory structure
WORK_DIR=$(mktemp -d)
RPM_BUILD="$WORK_DIR/rpmbuild"
mkdir -p "$RPM_BUILD"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

# Copy tarball to SOURCES
cp "$TARBALL_PATH" "$RPM_BUILD/SOURCES/"
log_info "Copied tarball to SOURCES/"

# Download Electron to SOURCES
log_info "Downloading Electron v${ELECTRON_VERSION}..."
wget -q -O "$RPM_BUILD/SOURCES/electron.zip" \
    "https://github.com/electron/electron/releases/download/v${ELECTRON_VERSION}/electron-v${ELECTRON_VERSION}-linux-x64.zip"

# Copy spec file
cp "$SCRIPT_DIR/claude-desktop-bin.spec" "$RPM_BUILD/SPECS/"

# Build RPM
log_info "Running rpmbuild..."
mkdir -p "$OUTPUT_DIR"

rpmbuild -bb \
    --define "_topdir $RPM_BUILD" \
    --define "pkg_version $VERSION" \
    --define "electron_version $ELECTRON_VERSION" \
    "$RPM_BUILD/SPECS/claude-desktop-bin.spec"

# Copy RPM to output
RPM_FILE=$(find "$RPM_BUILD/RPMS" -name "*.rpm" -type f | head -1)
if [ -z "$RPM_FILE" ]; then
    log_error "No RPM file found after build!"
    exit 1
fi

cp "$RPM_FILE" "$OUTPUT_DIR/"
RPM_BASENAME=$(basename "$RPM_FILE")
RPM_PATH="$OUTPUT_DIR/$RPM_BASENAME"

# Calculate SHA256
SHA256=$(sha256sum "$RPM_PATH" | cut -d' ' -f1)

log_info "RPM package built successfully!"
echo "  Version:  $VERSION"
echo "  Path:     $RPM_PATH"
echo "  SHA256:   $SHA256"

# Write build info
cat > "$OUTPUT_DIR/rpm-info.txt" << EOF
VERSION=$VERSION
RPM=$RPM_PATH
SHA256=$SHA256
EOF
