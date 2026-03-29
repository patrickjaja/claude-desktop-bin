#!/bin/bash
# install.sh — Set up the Claude Desktop APT repository
#
# Usage: curl -fsSL https://patrickjaja.github.io/claude-desktop-bin/install.sh | sudo bash

set -euo pipefail

REPO_URL="https://patrickjaja.github.io/claude-desktop-bin"
KEYRING_PATH="/etc/apt/keyrings/claude-desktop.gpg"
SOURCES_PATH="/etc/apt/sources.list.d/claude-desktop.list"

# Check root
if [ "$(id -u)" -ne 0 ]; then
  echo "Error: This script must be run as root (use sudo)."
  exit 1
fi

echo "Setting up Claude Desktop APT repository..."

# Download and install GPG key
mkdir -p /etc/apt/keyrings
curl -fsSL "$REPO_URL/gpg-key.asc" | gpg --dearmor -o "$KEYRING_PATH"
chmod 644 "$KEYRING_PATH"
echo "  GPG key installed to $KEYRING_PATH"

# Add repository source
cat > "$SOURCES_PATH" <<EOF
deb [signed-by=$KEYRING_PATH arch=amd64] $REPO_URL/deb/ ./
EOF
echo "  Repository added to $SOURCES_PATH"

# Update package lists
apt-get update -o Dir::Etc::sourcelist="$SOURCES_PATH" -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0" -qq

echo ""
echo "Done! Install Claude Desktop with:"
echo ""
echo "  sudo apt install claude-desktop-bin"
echo ""
echo "Future updates via: sudo apt update && sudo apt upgrade"
