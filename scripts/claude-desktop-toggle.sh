#!/bin/sh
# claude-desktop-toggle -- fast Quick Entry toggle for Claude Desktop on Linux.
#
# Connects to the Unix domain socket that Claude Desktop creates at startup.
# This bypasses the Electron process-spawn path and toggles Quick Entry in
# ~5-25 ms instead of ~300 ms.
#
# Usage: set this as your keyboard shortcut command instead of
#   claude-desktop --toggle-quick-entry
#
# Fallback: if the socket does not exist (Claude Desktop not running),
# falls through to `claude-desktop --toggle-quick-entry` which starts the app.

SOCK="/run/user/$(id -u)/claude-desktop-qe.sock"

if [ -S "$SOCK" ]; then
    # Try socat first (~2 ms startup), fall back to python3 (~25 ms startup).
    if command -v socat >/dev/null 2>&1; then
        socat /dev/null "UNIX-CLIENT:$SOCK" 2>/dev/null && exit 0
    fi
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "
import socket, os, sys
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.settimeout(0.5)
s.connect(sys.argv[1])
s.sendall(b'1')
s.close()
" "$SOCK" 2>/dev/null && exit 0
    fi
fi

# Fallback: standard Electron second-instance path (also starts the app if needed).
exec claude-desktop --toggle-quick-entry
