#!/usr/bin/env bash
# Claude Desktop launcher for Linux
#
# Handles Wayland/X11 detection, Electron flags, GPU fallback, and stale lock cleanup.
# Works across all packaging formats (Arch, RPM, DEB, AppImage, Nix) and both
# electron layouts:
#
#   bundled  — Electron runtime ships alongside the app, exec'd directly as
#              /usr/lib/claude-desktop-bin/com.anthropic.claude-desktop (its
#              resources/app.asar is loaded via ELECTRON_FORCE_IS_PACKAGED).
#   system   — Electron comes from $PATH or /usr/lib/claude-desktop/electron
#              and the app.asar is passed as the first argument.
#
# Environment variables:
#   CLAUDE_USE_XWAYLAND=1    - Force XWayland instead of native Wayland (escape hatch
#                              for users on Electron <40 that can't update; see below)
#   CLAUDE_MENU_BAR          - Menu bar mode: auto (default), visible, hidden
#   CLAUDE_DISABLE_GPU=1     - Disable GPU compositing (fixes white screen on some systems)
#   CLAUDE_DISABLE_GPU=full  - Disable GPU entirely (more aggressive fallback)
#   CLAUDE_ELECTRON          - Override path to Electron binary
#   CLAUDE_APP_ASAR          - Override path to app.asar (system layout only)

set -euo pipefail

# Reverse-URL application id for xdg-desktop-portal identification.
# Portals resolve unsandboxed apps via systemd-scope / cgroup name and match
# against the installed .desktop file. Must match the .desktop filename
# (minus the .desktop suffix) and the StartupWMClass entry in it.
APP_ID='com.anthropic.claude-desktop'

# ---------------------------------------------------------------------------
# Layout discovery — figure out where Electron and app.asar live
# ---------------------------------------------------------------------------
# Three possible layouts, probed in order:
#
#   1. Bundled (this repo's default build)
#      /usr/lib/claude-desktop-bin/com.anthropic.claude-desktop  ← electron
#      /usr/lib/claude-desktop-bin/resources/app.asar            ← app
#
#   2. System-electron build from this repo (or master-branch layout)
#      /usr/lib/claude-desktop-bin/app.asar                      ← app
#      electron                                                  ← from $PATH
#
#   3. Other distros that ship their own bundled electron
#      /usr/lib/claude-desktop/electron                          ← electron
#      /usr/lib/claude-desktop/{resources/,}app.asar             ← app
#
# CLAUDE_ELECTRON / CLAUDE_APP_ASAR env vars short-circuit the probe.

ELECTRON_BIN="${CLAUDE_ELECTRON:-}"
APP_ASAR="${CLAUDE_APP_ASAR:-}"

if [[ -z "$ELECTRON_BIN" ]]; then
    for candidate in \
        /usr/lib/claude-desktop-bin/com.anthropic.claude-desktop \
        /usr/lib/claude-desktop/electron \
        ; do
        if [[ -x "$candidate" ]]; then
            ELECTRON_BIN="$candidate"
            break
        fi
    done
    # Fall back to system electron on $PATH
    if [[ -z "$ELECTRON_BIN" ]]; then
        ELECTRON_BIN="electron"
    fi
fi

# Is the electron binary self-contained — does a resources/app.asar sit
# next to it? The bundled variant renames electron → com.anthropic.claude-
# desktop and places resources/ adjacent, so ELECTRON_FORCE_IS_PACKAGED
# lets it discover the asar without an explicit argv entry. We detect this
# regardless of whether ELECTRON_BIN came from auto-discovery or from
# CLAUDE_ELECTRON, so overriding the electron path still works.
ELECTRON_SELF_CONTAINED=0
ELECTRON_DIR=
if [[ "$ELECTRON_BIN" == /* ]]; then
    ELECTRON_DIR="$(dirname "$ELECTRON_BIN")"
    if [[ -f "$ELECTRON_DIR/resources/app.asar" ]]; then
        ELECTRON_SELF_CONTAINED=1
    fi
fi

if [[ "$ELECTRON_SELF_CONTAINED" = "0" && -z "$APP_ASAR" ]]; then
    for candidate in \
        /usr/lib/claude-desktop-bin/app.asar \
        /usr/lib/claude-desktop-bin/resources/app.asar \
        /usr/lib/claude-desktop/resources/app.asar \
        /usr/lib/claude-desktop/app.asar \
        ; do
        if [[ -f "$candidate" ]]; then
            APP_ASAR="$candidate"
            break
        fi
    done

    if [[ -z "$APP_ASAR" || ! -f "$APP_ASAR" ]]; then
        echo >&2 'claude-desktop: app.asar not found.'
        echo >&2 'Searched: /usr/lib/claude-desktop-bin/{,resources/}app.asar, /usr/lib/claude-desktop/{,resources/}app.asar'
        echo >&2 'Set CLAUDE_APP_ASAR=/path/to/app.asar to override.'
        exit 1
    fi
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
# Default: native Wayland on Wayland sessions, X11 on X11 sessions. Native
# Wayland uses xdg-desktop-portal's GlobalShortcuts API (implemented on GNOME,
# KDE, Hyprland).
#
# Known breakage: Electron <40 has a DBus signal-signature bug
# (electron/electron#49806, fixed in #49842 backported to 40.x/41.x). Global
# shortcuts register but Activated events never reach the app. We emit a loud
# warning to nudge users to upgrade instead of silently masking it with
# XWayland.
#
# Escape hatch: CLAUDE_USE_XWAYLAND=1 still forces XWayland for users who
# can't update Electron.

is_wayland=false
[[ -n "${WAYLAND_DISPLAY:-}" ]] && is_wayland=true

# Determine platform mode: x11, wayland, or xwayland
platform_mode=x11
if [[ $is_wayland == true ]]; then
    platform_mode=wayland

    if [[ "${CLAUDE_USE_XWAYLAND:-}" == '1' ]]; then
        # User explicitly wants XWayland — respect it unless compositor can't do it
        platform_mode=xwayland
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

# Force ARGB visuals so `transparent:true` popups (Quick Entry) render their
# outer window transparently on compositors that wouldn't otherwise expose
# alpha. No-op on X11 when already supported. Fixes the "opaque rectangle
# behind the rounded card" symptom (issue #39) on most Wayland configs.
ELECTRON_ARGS+=('--enable-transparent-visuals')


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

# Build the final argv. Self-contained bundled Electron already resolves its
# resources/app.asar via ELECTRON_FORCE_IS_PACKAGED; system/other layouts
# need the asar path as the first argument.
if [[ "$ELECTRON_SELF_CONTAINED" = "1" ]]; then
    LAUNCH_ARGV=("$ELECTRON_BIN" "${ELECTRON_ARGS[@]}" "$@")
else
    LAUNCH_ARGV=("$ELECTRON_BIN" "$APP_ASAR" "${ELECTRON_ARGS[@]}" "$@")
fi

log "Launching: ${LAUNCH_ARGV[*]}"

# Launch inside a named systemd user scope so xdg-desktop-portal identifies
# us via cgroup → scope unit name → matching .desktop file. Without this,
# the scope name embeds Electron's product name ("Claude"), which is not a
# reverse-URL and cannot be resolved to our .desktop entry by the portal.
# Fall back to direct exec in environments without user systemd (rare).
if command -v systemd-run &>/dev/null && [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
    exec systemd-run --user --scope --quiet \
        --unit="app-${APP_ID}-$$.scope" \
        --description='Claude Desktop' \
        -- "${LAUNCH_ARGV[@]}"
fi
log 'systemd-run unavailable — launching without scope; xdg-desktop-portal may fail to identify the app'
exec "${LAUNCH_ARGV[@]}"
