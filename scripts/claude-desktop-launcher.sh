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
#   COWORK_VM_BACKEND        - Cowork backend: native (default) or kvm (sandboxed VM)

set -euo pipefail

# Reverse-URL application id used everywhere identity matters:
#   - .desktop filename (minus the .desktop suffix)
#   - StartupWMClass in the .desktop
#   - Bundled Electron binary basename (Electron ignores Chromium's --class
#     flag; Wayland app_id and X11 WM_CLASS both derive from the binary name)
#   - systemd --user scope name (cgroup → portal identity)
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

# The bundled Electron binary must be named after APP_ID so Wayland app_id /
# X11 WM_CLASS match our .desktop file. Electron ignores Chromium's --class
# flag and derives the window identity from the binary name instead. We
# prefer the renamed binary; fall back to `electron` for mid-upgrade installs.
if [[ -z "$ELECTRON_BIN" ]]; then
    for candidate in \
        "/usr/lib/claude-desktop/${APP_ID}" \
        "/usr/lib/claude-desktop-bin/${APP_ID}" \
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
# Cowork daemon (bundled)
# ---------------------------------------------------------------------------
COWORK_BIN=""
COWORK_PID=""

if [[ -n "${ELECTRON_DIR:-}" ]]; then
    for candidate in \
        "$ELECTRON_DIR/cowork-svc-linux" \
        "$ELECTRON_DIR/resources/cowork-svc-linux" \
        ; do
        if [[ -x "$candidate" ]]; then
            COWORK_BIN="$candidate"
            break
        fi
    done
fi

if [[ -n "$COWORK_BIN" ]]; then
    if command -v systemctl &>/dev/null && systemctl --user is-active claude-cowork.service &>/dev/null 2>&1; then
        log "[MIGRATION] Standalone claude-cowork.service detected."
        log "[MIGRATION] Stopping it — the bundled daemon takes over."
        log "[MIGRATION] You can safely uninstall the standalone claude-cowork-service package."
        systemctl --user stop claude-cowork.service 2>/dev/null || true
        systemctl --user disable claude-cowork.service 2>/dev/null || true
    fi

    COWORK_BACKEND="${COWORK_VM_BACKEND:-native}"

    if [[ "$COWORK_BACKEND" == "kvm" ]]; then
        COWORK_SOCK="${XDG_RUNTIME_DIR:-/tmp}/cowork-kvm-service.sock"
    else
        COWORK_SOCK="${XDG_RUNTIME_DIR:-/tmp}/cowork-vm-service.sock"
    fi

    if [[ -S "$COWORK_SOCK" ]]; then
        if command -v socat &>/dev/null; then
            if ! socat -u OPEN:/dev/null UNIX-CONNECT:"$COWORK_SOCK" 2>/dev/null; then
                rm -f "$COWORK_SOCK"
                log "Removed stale cowork socket: $COWORK_SOCK"
            else
                log "Cowork socket already active — skipping daemon start"
                COWORK_BIN=""
            fi
        fi
    fi

    if [[ -n "$COWORK_BIN" ]]; then
        "$COWORK_BIN" --backend "$COWORK_BACKEND" &
        COWORK_PID=$!
        sleep 0.3
        if ! kill -0 "$COWORK_PID" 2>/dev/null; then
            wait "$COWORK_PID" 2>/dev/null
            COWORK_EXIT=$?
            log "WARNING: cowork daemon ($COWORK_BACKEND) exited immediately (exit $COWORK_EXIT)"

            if [[ "$COWORK_BACKEND" != "native" ]]; then
                echo >&2 "[cowork] $COWORK_BACKEND backend failed — falling back to native. Check daemon output above for details."
                COWORK_BACKEND=native
                export COWORK_VM_BACKEND=native
                COWORK_SOCK="${XDG_RUNTIME_DIR:-/tmp}/cowork-vm-service.sock"
                "$COWORK_BIN" --backend native &
                COWORK_PID=$!
                sleep 0.3
                if ! kill -0 "$COWORK_PID" 2>/dev/null; then
                    wait "$COWORK_PID" 2>/dev/null
                    log "WARNING: cowork daemon (native fallback) also failed"
                    echo >&2 "[cowork] Native fallback also failed. Cowork features will be unavailable."
                    COWORK_PID=""
                else
                    log "Started bundled cowork daemon (PID $COWORK_PID, native fallback)"
                fi
            else
                echo >&2 "[cowork] Daemon failed to start. Cowork features will be unavailable."
                COWORK_PID=""
            fi
        else
            log "Started bundled cowork daemon (PID $COWORK_PID, $COWORK_BACKEND backend)"
        fi
    fi
fi

cleanup() {
    if [[ -n "${COWORK_PID:-}" ]] && kill -0 "$COWORK_PID" 2>/dev/null; then
        log "Stopping bundled cowork daemon (PID $COWORK_PID)"
        kill "$COWORK_PID" 2>/dev/null || true
        wait "$COWORK_PID" 2>/dev/null || true
    fi
    if [[ -n "${ELECTRON_PID:-}" ]] && kill -0 "$ELECTRON_PID" 2>/dev/null; then
        kill "$ELECTRON_PID" 2>/dev/null || true
        wait "$ELECTRON_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

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

# Launch inside a named systemd user scope. The scope name (cgroup) gives
# xdg-desktop-portal a second identity signal alongside the Wayland app_id /
# X11 WM_CLASS, which come from the binary basename. Both must match APP_ID.
# Fall back to direct launch in environments without user systemd (rare).
#
# We avoid `exec` so the EXIT trap can clean up the bundled cowork daemon.
if command -v systemd-run &>/dev/null && [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
    systemd-run --user --scope --quiet \
        --unit="app-${APP_ID}-$$.scope" \
        --description='Claude Desktop' \
        -- "${LAUNCH_ARGV[@]}" &
    ELECTRON_PID=$!
else
    log 'systemd-run unavailable — launching without scope; xdg-desktop-portal may fail to identify the app'
    "${LAUNCH_ARGV[@]}" &
    ELECTRON_PID=$!
fi

wait $ELECTRON_PID 2>/dev/null
exit $?
