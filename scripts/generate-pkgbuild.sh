#!/bin/bash
set -e

VERSION="$1"
MAINTAINER_NAME="${AUR_USERNAME:-Patrick Jaja}"
MAINTAINER_EMAIL="${AUR_EMAIL:-patrickjajaa@gmail.com}"
SHA256SUM="$2"
DOWNLOAD_URL="$3"

if [ -z "$VERSION" ]; then
    echo "Usage: $0 <version> [sha256sum] [download_url]"
    exit 1
fi

if [ -z "$SHA256SUM" ]; then
    SHA256SUM="SKIP"
fi

if [ -z "$DOWNLOAD_URL" ]; then
    DOWNLOAD_URL="https://claude.ai/api/desktop/win32/x64/exe/latest/redirect"
fi

# Find the PKGBUILD.template file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="$SCRIPT_DIR/../PKGBUILD.template"

if [ ! -f "$TEMPLATE_FILE" ]; then
    echo "Error: PKGBUILD.template not found at $TEMPLATE_FILE"
    exit 1
fi

# Replace placeholders in the template
sed -e "s/{{VERSION}}/$VERSION/g" \
    -e "s/{{SHA256SUM}}/$SHA256SUM/g" \
    -e "s|{{DOWNLOAD_URL}}|$DOWNLOAD_URL|g" \
    -e "s/{{MAINTAINER_NAME}}/$MAINTAINER_NAME/g" \
    -e "s/{{MAINTAINER_EMAIL}}/$MAINTAINER_EMAIL/g" \
    "$TEMPLATE_FILE"