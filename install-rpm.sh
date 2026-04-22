#!/bin/bash
# install-rpm.sh — Set up the Claude Desktop RPM repository
#
# Usage: curl -fsSL https://patrickjaja.github.io/claude-desktop-bin/install-rpm.sh | sudo bash

set -euo pipefail

REPO_URL="https://patrickjaja.github.io/claude-desktop-bin"
REPO_FILE="/etc/yum.repos.d/claude-desktop.repo"

# Check root
if [ "$(id -u)" -ne 0 ]; then
  echo "Error: This script must be run as root (use sudo)."
  exit 1
fi

# Detect and validate architecture
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|aarch64) ;;
  *) echo "Error: Unsupported architecture: $ARCH (supported: x86_64, aarch64)"; exit 1 ;;
esac
echo "  Detected architecture: $ARCH"

echo "Setting up Claude Desktop RPM repository..."

# Import GPG key
rpm --import "$REPO_URL/gpg-key.asc"
echo "  GPG key imported"

# Add repository
cat > "$REPO_FILE" <<EOF
[claude-desktop]
name=Claude Desktop for Linux
baseurl=$REPO_URL/rpm/
enabled=1
gpgcheck=1
gpgkey=$REPO_URL/gpg-key.asc
repo_gpgcheck=1
metadata_expire=300
EOF
echo "  Repository added to $REPO_FILE"

# Update package cache
if command -v dnf &>/dev/null; then
  dnf makecache --repo=claude-desktop -q
elif command -v yum &>/dev/null; then
  yum makecache --disablerepo='*' --enablerepo=claude-desktop -q
fi

echo ""
echo "Done! Install Claude Desktop with:"
echo ""
echo "  sudo dnf install claude-desktop-bin"
echo ""
echo "Future updates via: sudo dnf upgrade claude-desktop-bin"
