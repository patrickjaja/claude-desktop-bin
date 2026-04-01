#!/bin/bash
# Setup ydotool v1.0.4 for Computer Use on Wayland (Ubuntu/Debian)
#
# Ubuntu/Debian ship ydotool 0.1.8 which is incompatible with Claude Desktop's
# Computer Use. This script builds v1.0.4 from source and configures the daemon.
#
# Usage: curl -fsSL https://raw.githubusercontent.com/patrickjaja/claude-desktop-bin/master/scripts/setup-ydotool.sh | sudo bash

set -euo pipefail

YDOTOOL_VERSION="v1.0.4"
BUILD_DIR="/tmp/ydotool-build-$$"
NEED_BUILD=1

# --- Preflight checks ---

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: run with sudo" >&2
    exit 1
fi

REAL_USER="${SUDO_USER:-$USER}"
RUNTIME_DIR="/run/user/$(id -u "$REAL_USER")"

# Check if v1.0+ is already installed
if command -v ydotool &>/dev/null && ydotool --help 2>&1 | grep -q 'debug'; then
    NEED_BUILD=0
    echo "ydotool v1.0+ is already installed."
fi

# --- Build (only if needed) ---

if [ "$NEED_BUILD" -eq 1 ]; then
    echo "Installing ydotool $YDOTOOL_VERSION..."

    # Stop running daemon before replacing binaries
    systemctl stop ydotoold 2>/dev/null || true
    pkill -x ydotoold 2>/dev/null || true

    apt-get install -y cmake gcc g++ git 2>&1 | tail -1
    rm -rf "$BUILD_DIR"
    git clone -q https://github.com/ReimuNotMoe/ydotool.git "$BUILD_DIR"
    cd "$BUILD_DIR"
    git -c advice.detachedHead=false checkout -q "$YDOTOOL_VERSION"
    mkdir build && cd build
    cmake .. -DCMAKE_BUILD_TYPE=Release >/dev/null 2>&1
    make -j"$(nproc)" >/dev/null 2>&1
    cp ydotool ydotoold /usr/bin/
    rm -rf "$BUILD_DIR"
fi

# --- uinput permissions ---

groupadd -f input
usermod -aG input "$REAL_USER" 2>/dev/null || true
echo 'KERNEL=="uinput", GROUP="input", MODE="0660"' > /etc/udev/rules.d/80-uinput.rules
udevadm control --reload-rules
udevadm trigger

# --- systemd service ---

cat > /etc/systemd/system/ydotoold.service << EOF
[Unit]
Description=ydotool daemon (Wayland input automation)

[Service]
ExecStart=/usr/bin/ydotoold --socket-path=${RUNTIME_DIR}/.ydotool_socket --socket-perm=0666
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now ydotoold

# --- Verify ---

sleep 1
if pgrep -x ydotoold &>/dev/null; then
    echo "Done! ydotoold is running. Restart Claude Desktop for Computer Use to pick it up."
else
    echo "Warning: ydotoold failed to start. Check: systemctl status ydotoold" >&2
    exit 1
fi
