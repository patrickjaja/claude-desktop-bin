#!/usr/bin/env bash
# Claude Desktop launcher for Linux
#
# Handles Wayland/X11 detection, Electron flags, GPU fallback, and stale lock cleanup.
# Works across all packaging formats (Arch, RPM, DEB, AppImage, Nix).
#
# Environment variables:
#   CLAUDE_USE_XWAYLAND=1    - Force XWayland instead of native Wayland (escape hatch
#                              for users on Electron <40 that can't update; see below)
#   CLAUDE_MENU_BAR          - Menu bar mode: auto (default), visible, hidden
#   CLAUDE_DISABLE_GPU=1     - Disable GPU compositing (fixes white screen on some systems)
#   CLAUDE_DISABLE_GPU=full  - Disable GPU entirely (more aggressive fallback)
#   CLAUDE_ELECTRON          - Override path to Electron binary
#   CLAUDE_APP_ASAR          - Override path to app.asar

set -euo pipefail

# Reverse-URL application id used everywhere identity matters:
#   - .desktop filename (minus the .desktop suffix)
#   - StartupWMClass in the .desktop
#   - Bundled Electron binary basename (Electron ignores Chromium's --class
#     flag; Wayland app_id and X11 WM_CLASS both derive from the binary name)
#   - systemd --user scope name (cgroup → portal identity)
APP_ID='com.anthropic.claude-desktop'

# ---------------------------------------------------------------------------
# Path discovery (supports Arch, RPM, DEB, AppImage layouts)
# ---------------------------------------------------------------------------

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
    if [[ -z "$ELECTRON_BIN" ]]; then
        ELECTRON_BIN="electron"
    fi
fi

if [[ -z "$APP_ASAR" ]]; then
    for candidate in \
        /usr/lib/claude-desktop-bin/resources/app.asar \
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
    echo >&2 'Searched: /usr/lib/claude-desktop-bin/resources/app.asar, /usr/lib/claude-desktop-bin/app.asar, /usr/lib/claude-desktop/resources/app.asar, /usr/lib/claude-desktop/app.asar'
    echo >&2 'Set CLAUDE_APP_ASAR=/path/to/app.asar to override.'
    exit 1
fi

# ---------------------------------------------------------------------------
# CLI subcommands: --install-gnome-hotkey / --uninstall-gnome-hotkey / --diagnose
# ---------------------------------------------------------------------------
# Early-exit subcommands intercepted BEFORE Electron is launched. These do
# not bring up the app — they configure the environment or report diagnostics.
#
# `--toggle-quick-entry` is deliberately NOT handled here: it must reach
# Electron so the second-instance handler (patched in index.js) can see it
# in argv and dispatch to the Quick Entry show function.
#
# Slot path for the gsettings GNOME custom keybinding. Stable across runs so
# --install/--uninstall can find it.
GNOME_HOTKEY_SLOT='/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/claude-desktop-quick-entry/'
GNOME_HOTKEY_ROOT='org.gnome.settings-daemon.plugins.media-keys'
GNOME_HOTKEY_DEFAULT='<Primary><Alt>space'

# Check that the session looks like GNOME (or at least has gnome-settings-daemon
# handling custom keybindings). Returns 0 if ok, 1 with a stderr message if not.
_require_gnome_gsettings() {
    if ! command -v gsettings &>/dev/null; then
        echo >&2 'claude-desktop: gsettings not found. This command requires GNOME / gnome-settings-daemon.'
        return 1
    fi
    if ! gsettings list-keys "$GNOME_HOTKEY_ROOT" 2>/dev/null | grep -q '^custom-keybindings$'; then
        echo >&2 "claude-desktop: schema '$GNOME_HOTKEY_ROOT' not available. This command requires GNOME."
        return 1
    fi
}

_install_gnome_hotkey() {
    local accel="${1:-$GNOME_HOTKEY_DEFAULT}"
    _require_gnome_gsettings || return 1

    # Python helper: safely parse the Python-list string from `gsettings get`
    # and append our slot if absent. Prints the new value as a Python list.
    local new_array
    if ! new_array=$(
        gsettings get "$GNOME_HOTKEY_ROOT" custom-keybindings \
        | python3 -c "
import ast, sys
raw = sys.stdin.read().strip()
# gsettings prints '@as []' for empty, otherwise a Python-list literal
if raw.startswith('@as '):
    raw = raw[len('@as '):]
try:
    arr = ast.literal_eval(raw)
except (ValueError, SyntaxError):
    print('PARSE_ERROR', file=sys.stderr)
    sys.exit(2)
slot = '$GNOME_HOTKEY_SLOT'
if slot not in arr:
    arr.append(slot)
print(repr(arr))
"
    ); then
        echo >&2 'claude-desktop: failed to parse existing custom-keybindings array'
        return 1
    fi

    gsettings set "$GNOME_HOTKEY_ROOT" custom-keybindings "$new_array"
    # Per-slot schema writes. Use ':' form to scope the schema to our slot.
    gsettings set "${GNOME_HOTKEY_ROOT}.custom-keybinding:${GNOME_HOTKEY_SLOT}" name 'Claude Desktop Quick Entry'
    gsettings set "${GNOME_HOTKEY_ROOT}.custom-keybinding:${GNOME_HOTKEY_SLOT}" command 'claude-desktop-toggle'
    gsettings set "${GNOME_HOTKEY_ROOT}.custom-keybinding:${GNOME_HOTKEY_SLOT}" binding "$accel"

    echo "Installed GNOME hotkey: $accel → claude-desktop-toggle"
    echo "Test it by pressing $accel from any window (Claude does not need to be focused)."
    echo "To change the accelerator later: claude-desktop --install-gnome-hotkey '<Super>space'"
    echo "To remove: claude-desktop --uninstall-gnome-hotkey"
    return 0
}

_uninstall_gnome_hotkey() {
    _require_gnome_gsettings || return 1

    local new_array
    if ! new_array=$(
        gsettings get "$GNOME_HOTKEY_ROOT" custom-keybindings \
        | python3 -c "
import ast, sys
raw = sys.stdin.read().strip()
if raw.startswith('@as '):
    raw = raw[len('@as '):]
try:
    arr = ast.literal_eval(raw)
except (ValueError, SyntaxError):
    print('PARSE_ERROR', file=sys.stderr)
    sys.exit(2)
slot = '$GNOME_HOTKEY_SLOT'
arr = [x for x in arr if x != slot]
print(repr(arr))
"
    ); then
        echo >&2 'claude-desktop: failed to parse existing custom-keybindings array'
        return 1
    fi

    gsettings set "$GNOME_HOTKEY_ROOT" custom-keybindings "$new_array"
    # Reset per-slot schema to drop our name/command/binding.
    gsettings reset-recursively "${GNOME_HOTKEY_ROOT}.custom-keybinding:${GNOME_HOTKEY_SLOT}" 2>/dev/null || true

    echo "Removed GNOME hotkey slot: $GNOME_HOTKEY_SLOT"
    return 0
}

_diagnose() {
    echo '=== claude-desktop --diagnose ==='
    echo
    echo '--- Session ---'
    echo "XDG_SESSION_TYPE = ${XDG_SESSION_TYPE:-(unset)}"
    echo "XDG_CURRENT_DESKTOP = ${XDG_CURRENT_DESKTOP:-(unset)}"
    echo "WAYLAND_DISPLAY = ${WAYLAND_DISPLAY:-(unset)}"
    echo "DISPLAY = ${DISPLAY:-(unset)}"
    echo
    echo '--- Binaries ---'
    echo "ELECTRON_BIN = $ELECTRON_BIN"
    # Don't run the binary — it IS the Claude app and launching it spawns
    # a new instance. Read the bundled version file instead.
    if [[ -n ${_electron_real:-} ]]; then
        local _vfile="$(dirname "$_electron_real")/version"
        if [[ -r $_vfile ]]; then
            echo "electron version file = $(<"$_vfile")"
        else
            echo "electron version file = (missing at $_vfile; parsed major=$electron_major)"
        fi
    fi
    echo "systemd-run = $(command -v systemd-run || echo '(missing)')"
    echo "gsettings = $(command -v gsettings || echo '(missing)')"
    echo "gdbus = $(command -v gdbus || echo '(missing)')"
    echo
    echo '--- App identity ---'
    echo "APP_ID = $APP_ID"
    local desktop_file="/usr/share/applications/${APP_ID}.desktop"
    if [[ -f $desktop_file ]]; then
        echo ".desktop file: $desktop_file (found)"
    else
        echo ".desktop file: $desktop_file (MISSING — portal identity will fail)"
    fi
    echo "APP_ASAR = $APP_ASAR"
    echo
    echo '--- xdg-desktop-portal GlobalShortcuts ---'
    if command -v gdbus &>/dev/null; then
        local portal_ver
        portal_ver=$(gdbus call --session --dest org.freedesktop.portal.Desktop \
            --object-path /org/freedesktop/portal/desktop \
            --method org.freedesktop.DBus.Properties.Get \
            org.freedesktop.portal.GlobalShortcuts version 2>&1 || echo '(failed)')
        echo "Portal version = $portal_ver"
    else
        echo '(gdbus not installed — cannot probe portal)'
    fi
    if command -v gsettings &>/dev/null; then
        echo
        echo '--- Registered portal shortcut apps (GNOME) ---'
        local apps
        apps=$(gsettings get org.gnome.settings-daemon.global-shortcuts applications 2>/dev/null || echo '(schema missing)')
        echo "org.gnome.settings-daemon.global-shortcuts applications = $apps"
        if [[ $apps == '@as []' ]]; then
            echo '(no app has completed the portal BindShortcuts+approval flow; expected on a fresh install)'
        fi
        echo
        echo '--- GNOME custom-keybinding slot ---'
        local cks
        cks=$(gsettings get "$GNOME_HOTKEY_ROOT" custom-keybindings 2>/dev/null || echo '(schema missing)')
        echo "custom-keybindings = $cks"
        if [[ $cks == *"$GNOME_HOTKEY_SLOT"* ]]; then
            echo 'claude-desktop hotkey slot: INSTALLED'
            echo "  name    = $(gsettings get "${GNOME_HOTKEY_ROOT}.custom-keybinding:${GNOME_HOTKEY_SLOT}" name 2>&1)"
            echo "  command = $(gsettings get "${GNOME_HOTKEY_ROOT}.custom-keybinding:${GNOME_HOTKEY_SLOT}" command 2>&1)"
            echo "  binding = $(gsettings get "${GNOME_HOTKEY_ROOT}.custom-keybinding:${GNOME_HOTKEY_SLOT}" binding 2>&1)"
        else
            echo 'claude-desktop hotkey slot: NOT INSTALLED'
            echo '(run: claude-desktop --install-gnome-hotkey)'
        fi
    fi
    echo
    echo '--- Recent launcher log (last 10 lines) ---'
    local logf="${XDG_CACHE_HOME:-$HOME/.cache}/claude-desktop/launcher.log"
    if [[ -f $logf ]]; then
        tail -10 "$logf"
    else
        echo '(no launcher.log yet)'
    fi
}

case "${1:-}" in
    --install-gnome-hotkey)
        shift
        _install_gnome_hotkey "$@"
        exit $?
        ;;
    --uninstall-gnome-hotkey)
        shift
        _uninstall_gnome_hotkey
        exit $?
        ;;
    --diagnose)
        shift
        # Run this subcommand even though it references variables (like
        # electron_major, platform_mode) that are set below; we re-read what
        # we need inside _diagnose. Electron version detection happens below
        # because both _diagnose and the normal launch path need it.
        _diagnose_requested=1
        ;;
esac

# ---------------------------------------------------------------------------
# Electron version detection
# ---------------------------------------------------------------------------
# Used below to decide whether native Wayland + GlobalShortcutsPortal is safe.
# electron/electron#49806 is a DBus signal-signature bug that causes global
# shortcuts to register but never deliver Activated events. Fix (#49842) was
# backported to 40.x and 41.x, not to 39.

electron_major=0
_electron_real="$ELECTRON_BIN"
[[ $_electron_real == electron ]] && _electron_real="$(command -v electron 2>/dev/null || true)"
if [[ -n $_electron_real ]]; then
    _version_file="$(dirname "$_electron_real")/version"
    if [[ -r $_version_file ]]; then
        electron_major=$(awk -F. 'NR==1{sub(/^v/,"",$1); print $1+0; exit}' "$_version_file" 2>/dev/null || echo 0)
    fi
    # Fall back to asking Electron itself (slightly slower, always works)
    if (( electron_major == 0 )); then
        electron_major=$("$_electron_real" --version 2>/dev/null | awk -F. 'NR==1{sub(/^v/,"",$1); print $1+0; exit}' || echo 0)
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

    if (( electron_major > 0 && electron_major < 40 )); then
        warn_msg="Electron $electron_major has a broken GlobalShortcutsPortal (electron/electron#49806, fixed in 40+/41+). Global hotkeys will only work when Claude Desktop has focus. Update your Electron package; Arch: sudo pacman -Syu electron. Escape hatch if you can't update: CLAUDE_USE_XWAYLAND=1."
        log "$warn_msg"
        echo >&2 "claude-desktop: $warn_msg"
    fi

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

# Now that platform_mode and electron_major are known, service the --diagnose
# subcommand if requested. Exits here — does not launch Electron.
if [[ -n ${_diagnose_requested:-} ]]; then
    echo "platform_mode = $platform_mode"
    echo "electron_major = $electron_major"
    _diagnose
    exit 0
fi

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
# Cowork socket cleanup (DISABLED)
# ---------------------------------------------------------------------------
# The intent was to clear stale cowork-vm-service sockets left by a crashed
# daemon. In practice the age-based fallback (used when socat is missing)
# deletes live sockets of healthy long-running services — a running daemon
# whose socket file is older than 24h is normal, not stale. Removing the
# filesystem entry leaves the kernel socket listening but makes new
# connect() calls return ENOENT.
#
# Left commented-out pending a proper health check (e.g. a Python
# connect-probe) rather than age-based heuristics.

# cowork_sock="${XDG_RUNTIME_DIR:-/tmp}/cowork-vm-service.sock"
#
# if [[ -S "$cowork_sock" ]]; then
#     stale=false
#     if command -v socat &>/dev/null; then
#         if ! socat -u OPEN:/dev/null UNIX-CONNECT:"$cowork_sock" 2>/dev/null; then
#             stale=true
#         fi
#     else
#         if [[ -n $(find "$cowork_sock" -mmin +1440 2>/dev/null) ]]; then
#             stale=true
#         fi
#     fi
#     if [[ $stale == true ]]; then
#         rm -f "$cowork_sock"
#         log 'Removed stale cowork-vm-service socket'
#     fi
# fi

# ---------------------------------------------------------------------------
# Launch
# ---------------------------------------------------------------------------

log "Launching: $ELECTRON_BIN $APP_ASAR ${ELECTRON_ARGS[*]} $*"

# Launch inside a named systemd user scope. The scope name (cgroup) gives
# xdg-desktop-portal a second identity signal alongside the Wayland app_id /
# X11 WM_CLASS, which come from the binary basename. Both must match APP_ID.
# Fall back to direct exec in environments without user systemd (rare).
if command -v systemd-run &>/dev/null && [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
    exec systemd-run --user --scope --quiet \
        --unit="app-${APP_ID}-$$.scope" \
        --description='Claude Desktop' \
        -- "$ELECTRON_BIN" "$APP_ASAR" "${ELECTRON_ARGS[@]}" "$@"
fi
log 'systemd-run unavailable — launching without scope; xdg-desktop-portal may fail to identify the app'
exec "$ELECTRON_BIN" "$APP_ASAR" "${ELECTRON_ARGS[@]}" "$@"
