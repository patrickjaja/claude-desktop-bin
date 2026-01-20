#!/bin/bash
#
# Generate PKGBUILD from template
#
# Usage: ./scripts/generate-pkgbuild.sh <version> <sha256sum> <download_url>
#
set -e

VERSION="$1"
SHA256SUM="$2"
DOWNLOAD_URL="$3"
MAINTAINER_NAME="${AUR_USERNAME:-Patrick Jaja}"
MAINTAINER_EMAIL="${AUR_EMAIL:-patrickjajaa@gmail.com}"

if [ -z "$VERSION" ]; then
    echo "Usage: $0 <version> <sha256sum> <download_url>" >&2
    echo "" >&2
    echo "Arguments:" >&2
    echo "  version       Package version (e.g., 1.0.3218)" >&2
    echo "  sha256sum     SHA256 checksum of the tarball" >&2
    echo "  download_url  URL to download the pre-patched tarball" >&2
    exit 1
fi

if [ -z "$SHA256SUM" ]; then
    SHA256SUM="SKIP"
fi

if [ -z "$DOWNLOAD_URL" ]; then
    DOWNLOAD_URL="https://github.com/patrickjaja/claude-desktop-bin/releases/download/v${VERSION}/claude-desktop-${VERSION}-linux.tar.gz"
fi

# Find the template
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TEMPLATE_FILE="$PROJECT_DIR/PKGBUILD.template"

if [ ! -f "$TEMPLATE_FILE" ]; then
    echo "Error: PKGBUILD.template not found at $TEMPLATE_FILE" >&2
    exit 1
fi

# Generate PKGBUILD by substituting placeholders
sed \
    -e "s/{{VERSION}}/$VERSION/g" \
    -e "s/{{SHA256SUM}}/$SHA256SUM/g" \
    -e "s|{{DOWNLOAD_URL}}|$DOWNLOAD_URL|g" \
    -e "s/{{MAINTAINER_NAME}}/$MAINTAINER_NAME/g" \
    -e "s/{{MAINTAINER_EMAIL}}/$MAINTAINER_EMAIL/g" \
    "$TEMPLATE_FILE"
