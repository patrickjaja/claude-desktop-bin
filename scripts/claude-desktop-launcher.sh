  #!/usr/bin/env bash
# Claude Desktop launcher for Linux
#
# Handles Wayland/X11 detection, Electron flags, GPU fallback, and stale lock cleanup.
# Works across all packaging formats (Arch, RPM, DEB, AppImage, Nix).
#
# Environment variables:
#   CLAUDE_USE_XWAYLAND=1    - Force XWayland instead of native Wayland (escape hatch)
#   CLAUDE_MENU_BAR          - Menu bar mode: auto (default), visible, hidden
#   CLAUDE_DISABLE_GPU=1     - Disable GPU compositing (fixes white screen on some systems)
#   CLAUDE_DISABLE_GPU=full  - Disable GPU entirely (more aggressive fallback)
#   CLAUDE_ELECTRON          - Override path to Electron binary
#   CLAUDE_APP_ASAR          - Override path to app.asar

set -euo pipefail

# ---------------------------------------------------------------------------
# Path discovery (supports Arch, RPM, DEB, AppImage layouts)
# ---------------------------------------------------------------------------

ELECTRON_BIN="${CLAUDE_ELECTRON:-}"
APP_ASAR="${CLAUDE_APP_ASAR:-}"

if [[ -z "$ELECTRON_BIN" ]]; then
    # Try bundled Electron first (RPM/DEB with bundled Electron)
    for candidate in /usr/lib/claude-desktop/electron; do
        if [[ -x "$candidate" ]]; then
            ELECTRON_BIN="$candidate"
            break
        fi
    done
    # Fall back to system Electron (Arch, DEB with system electron)
    if [[ -z "$ELECTRON_BIN" ]]; then
        ELECTRON_BIN="electron"
    fi
fi

if [[ -z "$APP_ASAR" ]]; then
    for candidate in \
        /usr/lib/claude-desktop-bin/app.asar \
        /usr/lib/claude-desktop/resources/app.asar \
        /usr/lib/claude-desktop/app.asar \
        ; do
        if [[ -f "$candidate" ]]; then
            APP_ASAR="$candidate"
            break
        fi
    done
fi

if [[ -z "$APP_ASAR" || ! -f "$APP_ASAR" ]]; then
    echo >&2 'claude-desktop: app.asar not found.'
    echo >&2 'Searched: /usr/lib/claude-desktop-bin/app.asar, /usr/lib/claude-desktop/resources/app.asar, /usr/lib/claude-desktop/app.asar'
    echo >&2 'Set CLAUDE_APP_ASAR=/path/to/app.asar to override.'
    exit 1
fi

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

LOG_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/claude-desktop"
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
# Default: native Wayland on Wayland sessions, X11 on X11 sessions.
# Global hotkeys use the xdg-desktop-portal GlobalShortcuts API on Wayland
# (works on KDE, Hyprland; Sway/GNOME portal support pending upstream).
# Set CLAUDE_USE_XWAYLAND=1 to force XWayland if you hit issues.
# Legacy: CLAUDE_USE_WAYLAND=1 is accepted but now a no-op (native is default).

is_wayland=false
[[ -n "${WAYLAND_DISPLAY:-}" ]] && is_wayland=true

# Determine platform mode: x11, wayland, or xwayland
platform_mode=x11
if [[ $is_wayland == true ]]; then
    platform_mode=wayland
    if [[ "${CLAUDE_USE_XWAYLAND:-}" == '1' ]]; then
        # User explicitly wants XWayland — respect it unless compositor can't do it
        platform_mode=xwayland
        # Niri has no XWayland support; override back to native Wayland
        desktop="${XDG_CURRENT_DESKTOP:-}"
        desktop="${desktop,,}"
        if [[ -n "${NIRI_SOCKET:-}" || "$desktop" == *niri* ]]; then
            log 'Niri detected — ignoring CLAUDE_USE_XWAYLAND (no XWayland support)'
            platform_mode=wayland
        fi
    fi
fi

# ---------------------------------------------------------------------------
# Build Electron arguments
# ---------------------------------------------------------------------------

ELECTRON_ARGS=()

# Disable CustomTitlebar for better Linux integration
ELECTRON_ARGS+=('--disable-features=CustomTitlebar')

case $platform_mode in
    x11)
        log 'X11 session detected'
        ;;
    xwayland)
        log 'Using X11 backend via XWayland (CLAUDE_USE_XWAYLAND=1)'
        ELECTRON_ARGS+=('--no-sandbox' '--ozone-platform=x11')
        ;;
    wayland)
        log 'Using native Wayland backend'
        ELECTRON_ARGS+=('--no-sandbox')
        ELECTRON_ARGS+=('--enable-features=UseOzonePlatform,WaylandWindowDecorations,GlobalShortcutsPortal')
        ELECTRON_ARGS+=('--ozone-platform=wayland')
        ELECTRON_ARGS+=('--enable-wayland-ime')
        ELECTRON_ARGS+=('--wayland-text-input-version=3')
        ;;
esac

# ---------------------------------------------------------------------------
# GPU compositing fallback
# ---------------------------------------------------------------------------
# Some GPU/driver combinations (notably GBM buffer creation failures on
# Wayland, common on Fedora KDE) cause a blank white window.
# See: https://github.com/patrickjaja/claude-desktop-bin/issues/13

case "${CLAUDE_DISABLE_GPU:-}" in
    1|compositing)
        log 'GPU compositing disabled (CLAUDE_DISABLE_GPU)'
        ELECTRON_ARGS+=('--disable-gpu-compositing')
        ;;
    full)
        log 'GPU fully disabled (CLAUDE_DISABLE_GPU=full)'
        ELECTRON_ARGS+=('--disable-gpu')
        ;;
esac

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

log "Launching: $ELECTRON_BIN $APP_ASAR ${ELECTRON_ARGS[*]} $*"
exec "$ELECTRON_BIN" "$APP_ASAR" "${ELECTRON_ARGS[@]}" "$@"
