#!/bin/bash
# install.sh — Set up the Claude Desktop APT repository
#
# Usage: curl -fsSL https://patrickjaja.github.io/claude-desktop-bin/install.sh | sudo bash

set -euo pipefail

REPO_URL="https://patrickjaja.github.io/claude-desktop-bin"
KEYRING_PATH="/etc/apt/keyrings/claude-desktop.gpg"
SOURCES_PATH="/etc/apt/sources.list.d/claude-desktop.sources"
OLD_LIST="/etc/apt/sources.list.d/claude-desktop.list"

# Check root
if [ "$(id -u)" -ne 0 ]; then
  echo "Error: This script must be run as root (use sudo)."
  exit 1
fi

echo "Setting up Claude Desktop APT repository..."

# Download and install GPG key.
# Download to a temp file and validate it parses as a GPG key BEFORE writing to
# the system keyring, so a truncated/corrupt download can't leave a broken key
# in /etc/apt/keyrings.
mkdir -p /etc/apt/keyrings
KEY_TMP="$(mktemp)"
trap 'rm -f "$KEY_TMP"' EXIT
curl -fsSL "$REPO_URL/gpg-key.asc" -o "$KEY_TMP"
if ! gpg --show-keys --with-fingerprint "$KEY_TMP" >/dev/null 2>&1; then
  echo "Error: downloaded GPG key failed to parse (corrupt or incomplete download)." >&2
  exit 1
fi
gpg --dearmor -o "$KEYRING_PATH" < "$KEY_TMP"
chmod 644 "$KEYRING_PATH"
echo "  GPG key installed to $KEYRING_PATH"

# Detect architecture for APT
case "$(dpkg --print-architecture)" in
  arm64)  APT_ARCH="arm64" ;;
  amd64)  APT_ARCH="amd64" ;;
  *)      echo "Error: Unsupported architecture: $(dpkg --print-architecture) (supported: amd64, arm64)"; exit 1 ;;
esac

# Remove legacy one-line .list file if present (migrating to DEB822 .sources)
if [ -f "$OLD_LIST" ]; then
  rm -f "$OLD_LIST"
  echo "  Removed legacy $OLD_LIST"
fi

# Add repository source (DEB822 format)
cat > "$SOURCES_PATH" <<EOF
Types: deb
URIs: $REPO_URL/deb/
Suites: ./
Signed-By: $KEYRING_PATH
Architectures: $APT_ARCH
EOF
echo "  Repository added to $SOURCES_PATH"

# Update only our repo's package list
APT_TMPDIR=$(mktemp -d)
ln -s "$SOURCES_PATH" "$APT_TMPDIR/"
apt-get update \
  -o Dir::Etc::sourcelist="/dev/null" \
  -o Dir::Etc::sourceparts="$APT_TMPDIR" \
  -o APT::Get::List-Cleanup="0" -qq
rm -rf "$APT_TMPDIR"

echo ""
echo "Done! Install Claude Desktop with:"
echo ""
echo "  sudo apt install claude-desktop-bin"
echo ""
echo "Future updates via: sudo apt update && sudo apt upgrade"
