#!/bin/bash
#
# Build an RPM package from the pre-patched Claude Desktop tarball.
#
# The tarball (produced by scripts/build-patched-tarball.sh from the official
# Linux .deb) already bundles the Electron runtime under electron/ and the
# patched app under app/. We do NOT download or verify a separate Electron zip.
#
# Usage: ./build-rpm.sh [--arch x86_64|aarch64] <tarball_path> <output_dir> [pkgrel]
#
# Requirements: rpmbuild, tar
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

# Parse optional --arch flag (default: x86_64)
RPM_ARCH="x86_64"
if [ "${1:-}" = "--arch" ]; then
    RPM_ARCH="$2"
    shift 2
fi

case "$RPM_ARCH" in
    x86_64|aarch64) ;;
    *)
        log_error "Unsupported architecture: $RPM_ARCH (supported: x86_64, aarch64)"
        exit 1
        ;;
esac

# Parse positional arguments
TARBALL_PATH="${1:-}"
OUTPUT_DIR="${2:-}"
PKGREL="${3:-1}"

if [ -z "$TARBALL_PATH" ] || [ -z "$OUTPUT_DIR" ]; then
    echo "Usage: $0 [--arch x86_64|aarch64] <tarball_path> <output_dir> [pkgrel]"
    echo ""
    echo "Arguments:"
    echo "  --arch        Target architecture (default: x86_64, also: aarch64)"
    echo "  tarball_path  Path to claude-desktop-VERSION-linux[-aarch64].tar.gz"
    echo "  output_dir    Directory to write .rpm package"
    echo "  pkgrel        Package release number (default: 1)"
    echo ""
    echo "Output:"
    echo "  <output_dir>/claude-desktop-bin-<version>-<pkgrel>.<arch>.rpm"
    exit 1
fi

if [ ! -f "$TARBALL_PATH" ]; then
    log_error "Tarball not found: $TARBALL_PATH"
    exit 1
fi

# Extract version from tarball filename (handles both -linux.tar.gz and -linux-aarch64.tar.gz)
VERSION=$(basename "$TARBALL_PATH" | sed -E 's/claude-desktop-([0-9]+\.[0-9]+\.[0-9]+)-linux(-aarch64)?\.tar\.gz/\1/')
TARBALL_NAME=$(basename "$TARBALL_PATH")
log_info "Building RPM package for version: $VERSION (arch: $RPM_ARCH)"

# Create rpmbuild directory structure
WORK_DIR=$(mktemp -d)
RPM_BUILD="$WORK_DIR/rpmbuild"
mkdir -p "$RPM_BUILD"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

# Copy tarball to SOURCES (keep its real basename so Source0 resolves it)
cp "$TARBALL_PATH" "$RPM_BUILD/SOURCES/$TARBALL_NAME"
log_info "Copied tarball to SOURCES/"

# Copy spec file
cp "$SCRIPT_DIR/claude-desktop-bin.spec" "$RPM_BUILD/SPECS/"

# Build RPM
log_info "Running rpmbuild..."
mkdir -p "$OUTPUT_DIR"

rpmbuild -bb \
    --target "$RPM_ARCH" \
    --define "_topdir $RPM_BUILD" \
    --define "pkg_version $VERSION" \
    --define "pkg_release $PKGREL" \
    --define "pkg_source $TARBALL_NAME" \
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
VERSION="$VERSION"
RPM="$RPM_PATH"
SHA256="$SHA256"
EOF
