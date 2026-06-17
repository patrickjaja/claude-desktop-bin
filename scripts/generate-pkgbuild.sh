#!/bin/bash
#
# Generate PKGBUILD from template
#
# Usage: ./scripts/generate-pkgbuild.sh <version> <sha256sum> <download_url> [pkgrel]
#
set -e

VERSION="$1"
SHA256SUM="$2"
DOWNLOAD_URL="$3"
PKGREL="${4:-1}"
MAINTAINER_NAME="${AUR_USERNAME:-Patrick Jaja}"
MAINTAINER_EMAIL="${AUR_EMAIL:-patrickjajaa@gmail.com}"

if [ -z "$VERSION" ]; then
    echo "Usage: $0 <version> <sha256sum> <download_url> [pkgrel]" >&2
    echo "" >&2
    echo "Arguments:" >&2
    echo "  version       Package version (e.g., 1.0.3218)" >&2
    echo "  sha256sum     SHA256 checksum of the tarball" >&2
    echo "  download_url  URL to download the pre-patched tarball" >&2
    echo "  pkgrel        Package release number (default: 1)" >&2
    exit 1
fi

if [ -z "$SHA256SUM" ]; then
    SHA256SUM="SKIP"
fi

if [ -z "$DOWNLOAD_URL" ]; then
    DOWNLOAD_URL="https://github.com/patrickjaja/claude-desktop-bin/releases/download/v${VERSION}/claude-desktop-${VERSION}-linux.tar.gz"
fi

# aarch64 tarball: env override or derive from x86_64 URL
SHA256SUM_AARCH64="${SHA256SUM_AARCH64:-SKIP}"
if [ -z "$DOWNLOAD_URL_AARCH64" ]; then
    DOWNLOAD_URL_AARCH64=$(echo "$DOWNLOAD_URL" | sed 's/-linux\.tar\.gz/-linux-aarch64.tar.gz/')
fi

# Find the template
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Resolve Electron version (pinned in .electron-version, overridable via env)
source "$SCRIPT_DIR/resolve-electron-version.sh"
TEMPLATE_FILE="$PROJECT_DIR/PKGBUILD.template"

if [ ! -f "$TEMPLATE_FILE" ]; then
    echo "Error: PKGBUILD.template not found at $TEMPLATE_FILE" >&2
    exit 1
fi

# Resolve the pinned Electron zip digests so makepkg verifies them natively
# (instead of the old 'SKIP'). Source of truth: .electron-shasums, kept in sync
# with .electron-version by scripts/update-electron-shasums.sh.
SHASUMS_FILE="$PROJECT_DIR/.electron-shasums"
if [ ! -f "$SHASUMS_FILE" ]; then
    echo "Error: .electron-shasums not found. Run scripts/update-electron-shasums.sh" >&2
    exit 1
fi
ELECTRON_SHA256_X64="$(awk -v n="electron-v${ELECTRON_VERSION}-linux-x64.zip" '$2 == n {print $1}' "$SHASUMS_FILE")"
ELECTRON_SHA256_ARM64="$(awk -v n="electron-v${ELECTRON_VERSION}-linux-arm64.zip" '$2 == n {print $1}' "$SHASUMS_FILE")"
if [ -z "$ELECTRON_SHA256_X64" ] || [ -z "$ELECTRON_SHA256_ARM64" ]; then
    echo "Error: missing Electron digest(s) for v${ELECTRON_VERSION} in $SHASUMS_FILE" >&2
    echo "  Run scripts/update-electron-shasums.sh after bumping .electron-version" >&2
    exit 1
fi

# Generate PKGBUILD by substituting placeholders
sed \
    -e "s/{{VERSION}}/$VERSION/g" \
    -e "s/{{PKGREL}}/$PKGREL/g" \
    -e "s/{{SHA256SUM}}/$SHA256SUM/g" \
    -e "s|{{DOWNLOAD_URL}}|$DOWNLOAD_URL|g" \
    -e "s/{{SHA256SUM_AARCH64}}/$SHA256SUM_AARCH64/g" \
    -e "s|{{DOWNLOAD_URL_AARCH64}}|$DOWNLOAD_URL_AARCH64|g" \
    -e "s/{{ELECTRON_VERSION}}/$ELECTRON_VERSION/g" \
    -e "s/{{ELECTRON_SHA256_X64}}/$ELECTRON_SHA256_X64/g" \
    -e "s/{{ELECTRON_SHA256_ARM64}}/$ELECTRON_SHA256_ARM64/g" \
    -e "s/{{MAINTAINER_NAME}}/$MAINTAINER_NAME/g" \
    -e "s/{{MAINTAINER_EMAIL}}/$MAINTAINER_EMAIL/g" \
    "$TEMPLATE_FILE"
