#!/bin/bash
#
# Update version and hash in package.nix after a new release
#
# Usage: ./update-hash.sh <version>
#
# Fetches the tarball from GitHub Releases and computes the Nix SRI hash.
#
set -euo pipefail

VERSION="${1:-}"

if [ -z "$VERSION" ]; then
    echo "Usage: $0 <version>"
    echo ""
    echo "Example: $0 1.1.3918"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_NIX="$SCRIPT_DIR/package.nix"

URL="https://github.com/patrickjaja/claude-desktop-bin/releases/download/v${VERSION}/claude-desktop-${VERSION}-linux.tar.gz"

echo "Fetching tarball: $URL"
HASH=$(nix-prefetch-url --unpack "$URL" 2>/dev/null | xargs nix hash to-sri --type sha256)

echo "Version: $VERSION"
echo "Hash:    $HASH"

# Update package.nix
sed -i -E "s|version = \"[^\"]+\"|version = \"$VERSION\"|" "$PACKAGE_NIX"
sed -i -E "s|hash = \"sha256-[^\"]+\"|hash = \"$HASH\"|" "$PACKAGE_NIX"

echo ""
echo "Updated $PACKAGE_NIX"
echo "Run 'nix build' to verify."
