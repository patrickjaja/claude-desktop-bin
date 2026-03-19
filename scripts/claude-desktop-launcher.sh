#!/usr/bin/env bash
# Claude Desktop launcher for Arch Linux (AUR package)
#
# Handles Wayland/X11 detection, Electron flags, and stale lock cleanup.
# Ported from claude-desktop-debian's launcher-common.sh.
#
# Environment variables:
#   CLAUDE_USE_WAYLAND=1   - Use native Wayland instead of XWayland
#   CLAUDE_MENU_BAR        - Menu bar mode: auto (default), visible, hidden

set -euo pipefail

APP_ASAR='/usr/lib/claude-desktop-bin/app.asar'

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

LOG_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/claude-desktop-bin"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/launcher.log"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"; }

# ---------------------------------------------------------------------------
# Display check
# ---------------------------------------------------------------------------

if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
    echo >&2 'claude-desktop: No display server detected.'
    echo >&2 'Both $DISPLAY and $WAYLAND_DISPLAY are unset.'
    echo >&2 'Run from within an X11 or Wayland session, not a TTY.'
    exit 1
fi

# ---------------------------------------------------------------------------
# Wayland / X11 detection
# ---------------------------------------------------------------------------

is_wayland=false
[[ -n "${WAYLAND_DISPLAY:-}" ]] && is_wayland=true

# Default: use X11/XWayland on Wayland compositors.
# XWayland preserves global hotkeys (Ctrl+Alt+Space for Quick Entry).
# Set CLAUDE_USE_WAYLAND=1 to use native Wayland (global hotkeys disabled).
use_xwayland=true
[[ "${CLAUDE_USE_WAYLAND:-}" == '1' ]] && use_xwayland=false

# Auto-detect compositors that have no XWayland support.
# Niri is the only known one; Sway and Hyprland have working XWayland.
# XDG_CURRENT_DESKTOP can be colon-separated (e.g. "niri:GNOME").
if [[ $is_wayland == true && $use_xwayland == true ]]; then
    desktop="${XDG_CURRENT_DESKTOP:-}"
    desktop="${desktop,,}"
    if [[ -n "${NIRI_SOCKET:-}" || "$desktop" == *niri* ]]; then
        log 'Niri detected - forcing native Wayland'
        use_xwayland=false
    fi
fi

# ---------------------------------------------------------------------------
# Build Electron arguments
# ---------------------------------------------------------------------------

ELECTRON_ARGS=()

# Disable CustomTitlebar for better Linux integration
ELECTRON_ARGS+=('--disable-features=CustomTitlebar')

if [[ $is_wayland != true ]]; then
    # Pure X11 session -- no extra flags needed
    log 'X11 session detected'
elif [[ $use_xwayland == true ]]; then
    # Wayland with XWayland (default) -- keeps global hotkeys working
    log 'Using X11 backend via XWayland (for global hotkey support)'
    ELECTRON_ARGS+=('--no-sandbox' '--ozone-platform=x11')
else
    # Native Wayland (user opted in, or Niri auto-detected)
    log 'Using native Wayland backend (global hotkeys may not work)'
    ELECTRON_ARGS+=('--no-sandbox')
    ELECTRON_ARGS+=('--enable-features=UseOzonePlatform,WaylandWindowDecorations')
    ELECTRON_ARGS+=('--ozone-platform=wayland')
    ELECTRON_ARGS+=('--enable-wayland-ime')
    ELECTRON_ARGS+=('--wayland-text-input-version=3')
fi

# ---------------------------------------------------------------------------
# Environment variables
# ---------------------------------------------------------------------------

export ELECTRON_FORCE_IS_PACKAGED=true
export ELECTRON_USE_SYSTEM_TITLE_BAR=1

# Pass through CLAUDE_MENU_BAR if set (auto/visible/hidden)
if [[ -n "${CLAUDE_MENU_BAR:-}" ]]; then
    export CLAUDE_MENU_BAR
fi

# ---------------------------------------------------------------------------
# SingletonLock cleanup
# ---------------------------------------------------------------------------
# Electron's requestSingleInstanceLock() silently quits if the lock is held.
# A stale lock from a crash blocks all launches with no error message.
# The lock is a symlink whose target encodes "hostname-PID".

config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/Claude"
lock_file="$config_dir/SingletonLock"

if [[ -L "$lock_file" ]]; then
    lock_target="$(readlink "$lock_file" 2>/dev/null)" || true
    lock_pid="${lock_target##*-}"
    if [[ "$lock_pid" =~ ^[0-9]+$ ]] && ! kill -0 "$lock_pid" 2>/dev/null; then
        rm -f "$lock_file"
        log "Removed stale SingletonLock (PID $lock_pid no longer running)"
    fi
fi

# ---------------------------------------------------------------------------
# Cowork socket cleanup
# ---------------------------------------------------------------------------
# The cowork-vm-service daemon creates a Unix socket. After a crash the
# socket file persists but nothing is listening (ECONNREFUSED vs ENOENT).

cowork_sock="${XDG_RUNTIME_DIR:-/tmp}/cowork-vm-service.sock"

if [[ -S "$cowork_sock" ]]; then
    stale=false
    if command -v socat &>/dev/null; then
        # Try connecting -- if it fails, the socket is stale
        if ! socat -u OPEN:/dev/null UNIX-CONNECT:"$cowork_sock" 2>/dev/null; then
            stale=true
        fi
    else
        # No socat: fall back to age-based check (>24 h = stale)
        if [[ -n $(find "$cowork_sock" -mmin +1440 2>/dev/null) ]]; then
            stale=true
        fi
    fi
    if [[ $stale == true ]]; then
        rm -f "$cowork_sock"
        log 'Removed stale cowork-vm-service socket'
    fi
fi

# ---------------------------------------------------------------------------
# Launch
# ---------------------------------------------------------------------------

log "Launching: electron $APP_ASAR ${ELECTRON_ARGS[*]} $*"
exec electron "$APP_ASAR" "${ELECTRON_ARGS[@]}" "$@"
