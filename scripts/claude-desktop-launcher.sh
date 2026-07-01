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
#   CLAUDE_DISABLE_SYSTEMD_SCOPE=1
#                            - Skip the systemd --user --scope wrapper (for
#                              sandboxes without access to the systemd private
#                              socket; portal app identity may not resolve)
#   CLAUDE_NATIVE_TITLEBAR=1 - Restore the native titlebar on Linux
#                              (frame:true + titleBarStyle:"default"). Default
#                              is the integrated titlebar with overlay. Also
#                              via --native-titlebar.

set -euo pipefail

# APP_ID is the bundled Electron binary basename only - cosmetic (argv[0] /
# /proc/self/exe). It is intentionally NOT the .desktop filename (see DESKTOP_ID
# below) and NOT the systemd scope name anymore (the scope now uses DESKTOP_ID so
# xdg-desktop-portal's cgroup→.desktop resolution finds the renamed file; see the
# Launch section).
#
# IMPORTANT: APP_ID is NOT the window's WM_CLASS / Wayland app_id either. That
# value is "claude-desktop" (verified via xprop/wmctrl) and comes from
# Chromium's GetXdgAppId(), which reads the app's desktopName
# ("claude-desktop.desktop" in app.asar package.json) and ignores the binary
# basename / --class / argv[0].
APP_ID='claude'

# The .desktop filename is a SEPARATE identity (DESKTOP_ID), computed below once
# the profile is known. As of issue #148 the default-profile launcher ships as
# "claude-desktop.desktop" so the filename equals the window's Wayland app_id
# ("claude-desktop"). On native Wayland there is no WM_CLASS, so GNOME/KDE match
# the window to its .desktop entry by app_id == .desktop filename; the old
# "claude.desktop" never matched and the dock/Alt-Tab icon fell back to a generic
# one. StartupWMClass (also "claude-desktop", set in every .desktop we write)
# covers X11/XWayland. So now BOTH match keys agree: filename == app_id (Wayland)
# and StartupWMClass == app_id (X11). See the DESKTOP_ID assignment after profile
# resolution below.

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
# Defined up here (before any caller) because functions like _appimage_integrate
# run during early startup and call log(); bash resolves a called function's name
# at call time, so a later definition would print "log: command not found" (#142).

LOG_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/claude-desktop"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/launcher.log"

# Rotate launcher.log if it grows too large. log() only ever appends (one or
# more lines per launch), so without a cap the file grows unboundedly over
# weeks of use. We keep a single rotated backup (launcher.log.old). This block
# runs on every startup and must never abort the launcher itself, so every
# step is guarded: a missing file or an odd stat must not stop Claude from
# opening. See issue #132 (the unbounded-growth half; the O(n^2) awk hang it
# also describes belongs to a different project and does not exist here).
_LOG_MAX_BYTES=$((2 * 1024 * 1024))  # 2 MiB
if [[ -f $LOG_FILE ]]; then
    _log_size=$(stat -c %s "$LOG_FILE" 2>/dev/null || echo 0)
    if [[ $_log_size =~ ^[0-9]+$ ]] && (( _log_size > _LOG_MAX_BYTES )); then
        mv -f "$LOG_FILE" "$LOG_FILE.old" 2>/dev/null || true
    fi
fi

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"; }

# ---------------------------------------------------------------------------
# Profile resolution
# ---------------------------------------------------------------------------
# A profile gives an instance its own userData dir (and therefore SingletonLock,
# logins, logs, spaces.json, custom themes), its own cowork + Quick Entry
# sockets, its own Claude Code config dir, and its own systemd scope name.
#
# Resolution order (later wins):
#   1. CLAUDE_PROFILE env var (so child processes inherit)
#   2. Invocation basename matching `claude-desktop-<name>` (symlink-launched)
#   3. --profile=<name> or --profile <name> on argv
#
# The bare name `default` is reserved and means "no suffix; paths unchanged
# from the v1 single-instance layout". Empty is the same as default. Valid
# profile names match [a-zA-Z0-9_-]+.

_invocation_basename="${0##*/}"
if [[ -z "${CLAUDE_PROFILE:-}" && "$_invocation_basename" =~ ^claude-desktop-([a-zA-Z0-9_-]+)$ ]]; then
    CLAUDE_PROFILE="${BASH_REMATCH[1]}"
fi

# Strip launcher-only flags from argv before subcommand dispatch and Electron
# pass-through:
#   --profile=NAME / --profile NAME: sets CLAUDE_PROFILE
#   --no-systemd-scope:              sets CLAUDE_DISABLE_SYSTEMD_SCOPE=1
#   --native-titlebar:               sets CLAUDE_NATIVE_TITLEBAR=1
_filtered_args=()
while (( $# > 0 )); do
    case "$1" in
        --profile=*)
            CLAUDE_PROFILE="${1#--profile=}"
            shift
            ;;
        --profile)
            shift
            if (( $# == 0 )); then
                echo >&2 'claude-desktop: --profile requires an argument'
                exit 2
            fi
            CLAUDE_PROFILE="$1"
            shift
            ;;
        --no-systemd-scope)
            CLAUDE_DISABLE_SYSTEMD_SCOPE=1
            shift
            ;;
        --native-titlebar)
            export CLAUDE_NATIVE_TITLEBAR=1
            shift
            ;;
        *)
            _filtered_args+=("$1")
            shift
            ;;
    esac
done
if (( ${#_filtered_args[@]} > 0 )); then
    set -- "${_filtered_args[@]}"
else
    set --
fi

if [[ "${CLAUDE_PROFILE:-}" == "default" ]]; then
    unset CLAUDE_PROFILE
fi
if [[ -n "${CLAUDE_PROFILE:-}" ]]; then
    if ! [[ "$CLAUDE_PROFILE" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo >&2 "claude-desktop: invalid profile name '$CLAUDE_PROFILE' (allowed: [a-zA-Z0-9_-])"
        exit 2
    fi
    profile_suffix="-${CLAUDE_PROFILE}"
    export CLAUDE_PROFILE
    # Relocate Claude Code's config dir so a profile's spawned `claude`
    # processes don't share state with the user's other profiles. Honored by
    # the @anthropic-ai/claude-code CLI (settings.json, projects/, sessions,
    # plugins). Inherited by child_process.spawn unless the JS explicitly
    # overrides env. Only set when a profile is active so default behavior
    # is unchanged. See anthropics/claude-code#2986 for known caveats.
    if [[ -z "${CLAUDE_CONFIG_DIR:-}" ]]; then
        export CLAUDE_CONFIG_DIR="$HOME/.claude${profile_suffix}"
    fi
else
    profile_suffix=""
fi

# Per-profile Electron userData (also resolves SingletonLock to the per-profile
# dir, so logins/logs/spaces.json/custom themes are auto-isolated). Must be
# computed early because subcommands like --diagnose reference it before the
# launch flow's SingletonLock cleanup block runs.
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/Claude${profile_suffix}"

# .desktop filename identity (see the DESKTOP_ID note in the APP_ID header).
# Default profile → "claude-desktop"; named profile → "claude-desktop-<name>".
# Distinct from APP_ID (the cosmetic binary/scope basename, still "claude").
DESKTOP_ID="claude-desktop${profile_suffix}"

# ---------------------------------------------------------------------------
# URL handler profile routing (SSO callback dispatch)
# ---------------------------------------------------------------------------
# When the system XDG handler fires `claude-desktop %u` for a claude:// URL
# (e.g. an SSO auth callback), the default profile would normally consume the
# URL, breaking login flows initiated from a named profile.
#
# The companion patch `fix_profile_url_routing.nim` makes each running profile
# write a marker file at $XDG_RUNTIME_DIR/claude-desktop-pending-auth-<name>
# whenever it opens an auth-ish URL via shell.openExternal. Here we look for
# the most recent fresh marker (<5 min old) and re-exec the launcher under
# that profile, so Electron's second-instance event delivers the URL to the
# right window.
#
# Skipped if a profile is already explicitly set, or if no claude:// URL is
# present in argv. See README.md ("SSO and URL routing" subsection) for
# semantics, limitations, and known failure modes.

if [[ -z "${CLAUDE_PROFILE:-}" ]]; then
    _claude_url=""
    for _a in "$@"; do
        case "$_a" in
            claude://*|claude-desktop://*)
                _claude_url="$_a"
                break
                ;;
        esac
    done
    if [[ -n "$_claude_url" ]]; then
        _runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
        # Most recently modified marker, max 5 min old, name validates as profile.
        _marker=$(find "$_runtime_dir" -maxdepth 1 -type f \
            -name 'claude-desktop-pending-auth-*' -mmin -5 \
            -printf '%T@ %p\n' 2>/dev/null \
            | sort -nr | head -1 | awk '{print $2}')
        if [[ -n "$_marker" && -f "$_marker" ]]; then
            _routed_profile="${_marker##*/claude-desktop-pending-auth-}"
            if [[ "$_routed_profile" =~ ^[a-zA-Z0-9_-]+$ ]]; then
                rm -f "$_marker"
                # The default profile uses the literal string "default" as
                # its marker suffix so its callbacks beat any stale named-
                # profile markers (otherwise an old work-profile marker
                # would hijack the default profile's SSO login). Don't
                # re-exec when the winning marker is the default profile —
                # we're already on it (no --profile flag was passed).
                if [[ "$_routed_profile" != "default" ]]; then
                    # Re-exec under the routed profile. The exec replaces
                    # this process so we don't need any further cleanup.
                    # The receiving profile will see the URL via its
                    # second-instance handler (or as initial argv if it
                    # isn't running yet).
                    exec "$0" "--profile=$_routed_profile" "$@"
                fi
            fi
        fi
    fi
fi

# ---------------------------------------------------------------------------
# Path discovery (supports Arch, RPM, DEB, AppImage layouts)
# ---------------------------------------------------------------------------

ELECTRON_BIN="${CLAUDE_ELECTRON:-}"
APP_ASAR="${CLAUDE_APP_ASAR:-}"

# The bundled Electron binary is named after APP_ID (cosmetic argv[0] / scope
# hint). NOTE: the binary basename does NOT set the window WM_CLASS - that comes
# from the app's desktopName ("claude-desktop"); see the APP_ID header above and
# issue #148. We prefer the renamed binary; fall back to `electron` for
# mid-upgrade installs.
#
# When a profile is active, prefer the user-local copy at
# ~/.local/lib/claude-desktop/<APP_ID>-<profile> created by --create-profile.
# (Intent was a per-profile WM_CLASS via the basename for separate icons/Alt-Tab
# groups; in practice all profiles still report "claude-desktop" because the
# shared app.asar desktopName wins - distinct per-profile WM_CLASS would need a
# per-profile desktopName/CHROME_DESKTOP override, as in fix_quick_entry_app_id.nim.)
if [[ -z "$ELECTRON_BIN" ]]; then
    candidates=()
    if [[ -n "$profile_suffix" ]]; then
        candidates+=("$HOME/.local/lib/claude-desktop/${APP_ID}${profile_suffix}")
    fi
    candidates+=(
        "/usr/lib/claude-desktop/${APP_ID}"
        "/usr/lib/claude-desktop-bin/${APP_ID}"
        /usr/lib/claude-desktop/electron
    )
    for candidate in "${candidates[@]}"; do
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
# CLI subcommands: --install-gnome-hotkey / --uninstall-gnome-hotkey / --toggle / --diagnose
# ---------------------------------------------------------------------------
# Early-exit subcommands intercepted BEFORE Electron is launched. These do
# not bring up the app — they configure the environment or report diagnostics.
#
# `--toggle` tries the fast socket path first (~5-25 ms). If the socket is
# unavailable (app not running), it falls through to launch Electron with
# --toggle in argv so the patched second-instance / first-instance handler
# can fire the Quick Entry show function.
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
    gsettings set "${GNOME_HOTKEY_ROOT}.custom-keybinding:${GNOME_HOTKEY_SLOT}" command 'claude-desktop --toggle'
    gsettings set "${GNOME_HOTKEY_ROOT}.custom-keybinding:${GNOME_HOTKEY_SLOT}" binding "$accel"

    echo "Installed GNOME hotkey: $accel → claude-desktop --toggle"
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

_profile_paths() {
    # Outputs the four files associated with a profile to stdout, one per line.
    # Order: electron-symlink, launcher-symlink, desktop-file, config-dir.
    local name="$1"
    echo "$HOME/.local/lib/claude-desktop/${APP_ID}-${name}"
    echo "$HOME/.local/bin/claude-desktop-${name}"
    echo "$HOME/.local/share/applications/claude-desktop-${name}.desktop"
    echo "${XDG_CONFIG_HOME:-$HOME/.config}/Claude-${name}"
}

# Try to materialise a per-profile Electron binary at $2, taking the cheapest
# option that produces a real (not-symlink) inode at the destination so that
# /proc/self/exe resolves to the per-profile path. Sets the global _link_kind
# to a human-readable label. Returns 0 on success, 1 on failure.
_materialise_profile_binary() {
    local src="$1" dst="$2"
    _link_kind=""
    if ln "$src" "$dst" 2>/dev/null; then
        _link_kind="hardlink (~0 disk used)"
        return 0
    fi
    if cp --reflink=always "$src" "$dst" 2>/dev/null; then
        _link_kind="reflink (CoW, ~0 disk used)"
        return 0
    fi
    if cp "$src" "$dst" 2>/dev/null; then
        _link_kind="copy ($(du -h "$dst" | cut -f1))"
        return 0
    fi
    rm -f "$dst"
    return 1
}

# Refresh the per-profile directory's sibling symlinks. Electron's
# RPATH=$ORIGIN looks for libffmpeg.so etc as siblings of the binary, and
# Chromium reads its .pak / locales / resources / version from the same
# directory. We populate them as symlinks back to the system install. This
# function is idempotent: it (re)creates only links that are missing or
# point at the wrong target, and skips the per-profile binary itself plus
# any other profile binaries that already live there.
_mirror_profile_siblings() {
    local src_dir="$1" dst_dir="$2" orig_bn="$3"
    local entry bn target
    for entry in "$src_dir"/*; do
        [[ -e "$entry" ]] || continue
        bn="$(basename "$entry")"
        [[ "$bn" == "$orig_bn" ]] && continue
        case "$bn" in "${APP_ID}-"*) continue ;; esac
        target="$(readlink "$dst_dir/$bn" 2>/dev/null || true)"
        if [[ "$target" != "$entry" ]]; then
            rm -f "$dst_dir/$bn"
            ln -s "$entry" "$dst_dir/$bn"
        fi
    done
}

# Resolve the canonical (system-installed) Electron binary, ignoring any
# per-profile copy. Mirrors the path-discovery candidate list. Returns the
# first executable hit on stdout, or empty if none found.
_canonical_electron_bin() {
    local c
    for c in \
        "/usr/lib/claude-desktop/${APP_ID}" \
        "/usr/lib/claude-desktop-bin/${APP_ID}" \
        "/usr/lib/claude-desktop/electron"; do
        if [[ -x "$c" ]]; then
            echo "$c"
            return 0
        fi
    done
    return 1
}

# At every launch under a named profile, repair the per-profile install if it
# has gone stale. Triggers:
#   - Canonical binary newer than per-profile copy (package upgrade refreshed
#     /usr/lib/claude-desktop-bin/<APP_ID> while ~/.local/lib still points
#     at the old version → version mismatch with app.asar at runtime).
#   - Per-profile binary present but no longer executable (e.g. NixOS rebuild
#     replaced the store path; symlinks pointing into /nix/store dangle).
#   - Any sibling symlink target missing (same Nix scenario, or AppImage
#     mount-point churn).
# When a refresh runs, it leaves a one-line note on stderr so the user can
# correlate post-upgrade hiccups. Failures fall through to whatever the
# next launch attempt sees; no fatal exit.
_refresh_profile_binary_if_stale() {
    [[ -z "$profile_suffix" ]] && return 0
    local profile_bin="$HOME/.local/lib/claude-desktop/${APP_ID}${profile_suffix}"
    [[ -e "$profile_bin" ]] || return 0  # not yet --create-profile'd
    local canonical
    canonical="$(_canonical_electron_bin)" || return 0  # no system install? bail

    local need_refresh=0 reason=""
    if [[ ! -x "$profile_bin" ]]; then
        need_refresh=1; reason="per-profile binary not executable (Nix store moved?)"
    elif [[ "$canonical" -nt "$profile_bin" ]]; then
        need_refresh=1; reason="canonical Electron is newer (package upgrade?)"
    else
        # Walk siblings; if any symlink dangles, full refresh.
        local entry bn target
        for entry in "$(dirname "$profile_bin")"/*; do
            [[ -L "$entry" ]] || continue
            target="$(readlink "$entry" 2>/dev/null)"
            if [[ -z "$target" || ! -e "$target" ]]; then
                need_refresh=1; reason="sibling symlink dangling: $entry"
                break
            fi
        done
    fi

    (( need_refresh )) || return 0
    log "Refreshing stale profile '$CLAUDE_PROFILE': $reason"
    echo >&2 "claude-desktop: refreshing stale per-profile binary ($reason)"

    rm -f "$profile_bin"
    if ! _materialise_profile_binary "$canonical" "$profile_bin"; then
        echo >&2 "claude-desktop: failed to refresh per-profile binary; falling back to canonical for this launch"
        return 1
    fi
    _mirror_profile_siblings "$(dirname "$canonical")" "$(dirname "$profile_bin")" "$(basename "$canonical")"
    log "Refreshed via $_link_kind"
    return 0
}

# ---------------------------------------------------------------------------
# AppImage desktop integration (protocol handler + app menu entry)
# ---------------------------------------------------------------------------
_APPIMAGE_DESKTOP_FILE="$HOME/.local/share/applications/${DESKTOP_ID}.desktop"
_APPIMAGE_ICON_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"

_appimage_integrate() {
    local appimage_path="${CLAUDE_APPIMAGE_PATH:-}"
    local quiet="${1:-}"

    if [[ -z "$appimage_path" ]]; then
        if [[ "$quiet" != "quiet" ]]; then
            echo >&2 "claude-desktop: not running as AppImage (CLAUDE_APPIMAGE_PATH unset)."
            echo >&2 "  This command is only needed for AppImage installs."
        fi
        return 1
    fi

    if [[ ! -f "$appimage_path" ]]; then
        log "AppImage integrate: path does not exist: $appimage_path"
        if [[ "$quiet" != "quiet" ]]; then
            echo >&2 "claude-desktop: AppImage not found at $appimage_path"
        fi
        return 1
    fi

    if [[ -f "/usr/share/applications/${DESKTOP_ID}.desktop" ]]; then
        log "AppImage integrate: system .desktop exists - skipping"
        if [[ "$quiet" != "quiet" ]]; then
            echo "System package already provides ${DESKTOP_ID}.desktop - AppImage integration skipped."
            echo "(The system package's protocol handler takes priority.)"
        fi
        return 0
    fi

    local desired_exec="Exec=${appimage_path} %u"

    if [[ -f "$_APPIMAGE_DESKTOP_FILE" ]]; then
        local current_exec
        current_exec=$(grep '^Exec=' "$_APPIMAGE_DESKTOP_FILE" 2>/dev/null | head -1)
        if [[ "$current_exec" == "$desired_exec" ]]; then
            log "AppImage integrate: .desktop up to date ($appimage_path)"
            if [[ "$quiet" != "quiet" ]]; then
                echo "Desktop integration already up to date."
                echo "  File: $_APPIMAGE_DESKTOP_FILE"
                echo "  Exec: $appimage_path %u"
            fi
            return 0
        fi
        log "AppImage integrate: updating .desktop (path changed)"
    fi

    mkdir -p "$(dirname "$_APPIMAGE_DESKTOP_FILE")"

    # Content aligned to the official .deb's .desktop (issue #148), adapted for
    # AppImage: Exec= and the Action Exec lines point at the AppImage path
    # instead of /usr/bin/claude-desktop. We keep %u (not the official %U) on the
    # main Exec= so it matches $desired_exec in the up-to-date check above;
    # the launcher handles a single claude:// URL either way.
    cat > "$_APPIMAGE_DESKTOP_FILE" <<DESKTOP_EOF
[Desktop Entry]
Name=Claude
Comment=Desktop application for Claude.ai
GenericName=AI Assistant
Keywords=AI;Chat;Assistant;Claude;Code;LLM;
${desired_exec}
Icon=claude-desktop
Type=Application
StartupNotify=true
StartupWMClass=claude-desktop
SingleMainWindow=true
Categories=Utility;Development;
MimeType=x-scheme-handler/claude;
Actions=NewChat;NewCode;

[Desktop Action NewChat]
Name=New chat
Exec=${appimage_path} claude://claude.ai/new

[Desktop Action NewCode]
Name=New Claude Code session
Exec=${appimage_path} claude://code/new
DESKTOP_EOF

    local appimage_icon=""
    local here="${CLAUDE_ELECTRON%/*}"
    if [[ -n "$here" ]]; then
        local appdir="${here}/../../.."
        if [[ -f "$appdir/claude-desktop.png" ]]; then
            appimage_icon="$appdir/claude-desktop.png"
        elif [[ -f "$appdir/usr/share/icons/hicolor/256x256/apps/claude-desktop.png" ]]; then
            appimage_icon="$appdir/usr/share/icons/hicolor/256x256/apps/claude-desktop.png"
        fi
    fi
    if [[ -n "$appimage_icon" && -f "$appimage_icon" ]]; then
        mkdir -p "$_APPIMAGE_ICON_DIR"
        cp "$appimage_icon" "$_APPIMAGE_ICON_DIR/claude-desktop.png" 2>/dev/null || true
    fi

    if command -v update-desktop-database &>/dev/null; then
        update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
    fi

    if command -v xdg-mime &>/dev/null; then
        xdg-mime default "${DESKTOP_ID}.desktop" x-scheme-handler/claude 2>/dev/null || true
    fi

    log "AppImage integrate: registered ${_APPIMAGE_DESKTOP_FILE} -> ${appimage_path}"
    if [[ "$quiet" != "quiet" ]]; then
        echo "Desktop integration installed."
        echo "  File: $_APPIMAGE_DESKTOP_FILE"
        echo "  Exec: $appimage_path %u"
        echo "  Protocol: claude:// -> Claude Desktop (AppImage)"
        echo
        echo "The claude:// protocol handler is now active."
        echo "To remove: claude-desktop --unintegrate"
    fi
    return 0
}

_appimage_unintegrate() {
    local removed=0

    if [[ -f "$_APPIMAGE_DESKTOP_FILE" ]]; then
        local exec_line
        exec_line=$(grep '^Exec=' "$_APPIMAGE_DESKTOP_FILE" 2>/dev/null | head -1)
        if [[ "$exec_line" == *".AppImage"* ]]; then
            rm -f "$_APPIMAGE_DESKTOP_FILE"
            echo "Removed: $_APPIMAGE_DESKTOP_FILE"
            removed=$((removed + 1))
        else
            echo >&2 "claude-desktop: $_APPIMAGE_DESKTOP_FILE does not point to an AppImage - not removing."
            echo >&2 "  Current Exec=: $exec_line"
            return 1
        fi
    fi

    local icon_file="$_APPIMAGE_ICON_DIR/claude-desktop.png"
    if [[ -f "$icon_file" ]]; then
        rm -f "$icon_file"
        echo "Removed: $icon_file"
        removed=$((removed + 1))
    fi

    if (( removed == 0 )); then
        echo "No AppImage integration found to remove."
        return 0
    fi

    if command -v update-desktop-database &>/dev/null; then
        update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
    fi

    echo "Desktop integration removed."
    return 0
}

_create_profile() {
    local name="$1"
    if [[ -z "$name" || "$name" == "default" ]]; then
        echo >&2 "claude-desktop: profile name must be non-empty and not 'default'"
        return 2
    fi
    if ! [[ "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo >&2 "claude-desktop: invalid profile name '$name' (allowed: [a-zA-Z0-9_-])"
        return 2
    fi

    local launcher_path
    launcher_path="$(readlink -f "$0" 2>/dev/null || echo "$0")"
    if [[ ! -x "$launcher_path" ]]; then
        echo >&2 "claude-desktop: cannot resolve launcher path ($0)"
        return 1
    fi
    if [[ "$ELECTRON_BIN" == "electron" || ! -x "$ELECTRON_BIN" ]]; then
        echo >&2 "claude-desktop: cannot resolve bundled Electron binary; --create-profile requires an installed package"
        return 1
    fi

    local electron_bin_path="$HOME/.local/lib/claude-desktop/${APP_ID}-${name}"
    local launcher_link="$HOME/.local/bin/claude-desktop-${name}"
    local desktop_file="$HOME/.local/share/applications/claude-desktop-${name}.desktop"

    if [[ -e "$electron_bin_path" || -e "$launcher_link" || -e "$desktop_file" ]]; then
        echo >&2 "claude-desktop: profile '$name' already exists. Use --delete-profile=$name first to recreate."
        return 1
    fi

    mkdir -p "$(dirname "$electron_bin_path")" "$(dirname "$launcher_link")" "$(dirname "$desktop_file")"

    # The per-profile Electron binary is a real file (not a symlink) so
    # /proc/self/exe resolves to the per-profile path (distinct argv[0] / scope).
    # This mirrors how Chrome does multi-channel (google-chrome-stable /
    # google-chrome-beta are real copies). NOTE: this alone does NOT give each
    # profile a distinct WM_CLASS - Chromium's app_id comes from the shared
    # app.asar desktopName ("claude-desktop"), not the binary basename, so the
    # WM still groups all profiles as one app. See issue #148 / the discovery
    # comment above for the per-profile-desktopName follow-up.
    #
    # Strategy: hardlink first (zero-cost, same fs only), reflink second
    # (zero-cost on btrfs/xfs), copy fallback (typically ~200 MB per profile).
    if ! _materialise_profile_binary "$ELECTRON_BIN" "$electron_bin_path"; then
        echo >&2 "claude-desktop: failed to materialise per-profile binary at $electron_bin_path"
        return 1
    fi
    local link_kind="$_link_kind"

    # Mirror the other files in the Electron install dir back as symlinks so
    # the per-profile binary can find its sibling shared libraries
    # (RPATH=$ORIGIN looks for libffmpeg.so, libEGL.so, etc.) and Chromium can
    # find its data files (.pak, locales/, resources/, version, icudtl.dat).
    # Profile-agnostic: shared across all profiles in the lib dir.
    _mirror_profile_siblings \
        "$(dirname "$ELECTRON_BIN")" \
        "$(dirname "$electron_bin_path")" \
        "$(basename "$ELECTRON_BIN")"

    ln -s "$launcher_path" "$launcher_link"

    # Try to find the default-profile system .desktop to inherit Icon=, etc.
    # The installed default file is "claude-desktop.desktop" (issue #148), not
    # "${APP_ID}.desktop" - APP_ID is now only the binary/scope basename.
    local source_desktop=""
    for c in \
        "/usr/share/applications/claude-desktop.desktop" \
        "$HOME/.local/share/applications/claude-desktop.desktop"; do
        if [[ -f "$c" ]]; then
            source_desktop="$c"
            break
        fi
    done

    # Use an absolute Exec= path so the entry works without ~/.local/bin in
    # PATH and so GNOME Shell's Overview accepts it. Pass --profile=NAME
    # directly to the system launcher rather than relying on the per-profile
    # symlink basename, since the symlink isn't on PATH for GNOME Shell.
    local exec_line="Exec=${launcher_path} --profile=${name} %u"

    if [[ -n "$source_desktop" ]]; then
        # Rewrite Name and Exec; drop MimeType= so the claude:// scheme remains
        # owned by the system .desktop. The launcher routes incoming URLs to the
        # right profile via the auth marker; if named profiles also claimed the
        # scheme, xdg-mime ordering would short-circuit our routing for whichever
        # entry got picked first. Also strip the Actions= key and every [Desktop
        # Action ...] block: their Exec= lines hardcode the default `claude-desktop`
        # binary, so a named profile's right-click "New chat" would open in the
        # default profile. Simpler to drop them than to rewrite each per-action Exec.
        #
        # StartupWMClass is left as the inherited "claude-desktop" on purpose: the
        # window's live app_id is "claude-desktop" for every profile (the shared
        # app.asar desktopName wins), so a per-profile "claude-<name>" WMClass
        # would never match the window. A distinct per-profile app_id needs a
        # per-profile desktopName override (out of scope for #148).
        awk -v name="$name" -v execline="$exec_line" '
            BEGIN { FS=OFS="="; drop=0 }
            /^\[Desktop Action / { drop=1; next }   # drop the whole action block
            /^\[Desktop Entry\]/ { drop=0 }
            drop { next }
            /^Name=/     { print "Name=Claude (" name ")"; next }
            /^Exec=/     { print execline; next }
            /^MimeType=/ { next }
            /^Actions=/  { next }
            { print }
        ' "$source_desktop" > "$desktop_file"
    else
        cat > "$desktop_file" <<EOF
[Desktop Entry]
Name=Claude ($name)
${exec_line}
Terminal=false
Type=Application
Icon=claude-desktop
StartupWMClass=claude-desktop
Categories=Utility;Development;
EOF
    fi

    if command -v update-desktop-database &>/dev/null; then
        update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
    fi

    echo "Created profile '$name'."
    echo "  Electron binary:  $electron_bin_path  ($link_kind)"
    echo "  Launcher symlink: $launcher_link"
    echo "  Desktop file:     $desktop_file"
    echo
    echo "Launch from your application menu (entry: 'Claude ($name)'),"
    echo "or run:    $launcher_path --profile=$name"
    if [[ ":$PATH:" == *":$HOME/.local/bin:"* ]]; then
        echo "or:        claude-desktop-$name"
    fi
    return 0
}

_delete_profile() {
    local name="$1"
    if [[ -z "$name" || "$name" == "default" ]]; then
        echo >&2 "claude-desktop: cannot delete default; profile name required"
        return 2
    fi
    if ! [[ "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo >&2 "claude-desktop: invalid profile name '$name'"
        return 2
    fi

    local electron_link="$HOME/.local/lib/claude-desktop/${APP_ID}-${name}"
    local launcher_link="$HOME/.local/bin/claude-desktop-${name}"
    local desktop_file="$HOME/.local/share/applications/claude-desktop-${name}.desktop"

    local removed=0
    for f in "$electron_link" "$launcher_link" "$desktop_file"; do
        if [[ -L "$f" || -f "$f" ]]; then
            rm -f "$f"
            echo "Removed: $f"
            # NOTE: do NOT use ((removed++)) here -- post-increment returns
            # the OLD value, which is 0 on the first hit. Under `set -e` that
            # makes the whole script exit (treating 0 as a failed command),
            # so only the first artifact would ever get removed per call.
            # Use arithmetic assignment to always return non-zero exit status.
            removed=$((removed + 1))
        fi
    done

    if (( removed == 0 )); then
        echo >&2 "claude-desktop: profile '$name' has no installed entry points (nothing to remove)"
    fi

    if command -v update-desktop-database &>/dev/null; then
        update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
    fi

    echo
    echo "User data preserved at: ${XDG_CONFIG_HOME:-$HOME/.config}/Claude-${name}"
    echo "Code config preserved at: $HOME/.claude-${name}"
    echo "Remove those manually if you also want to delete login state and history."
    return 0
}

_list_profiles() {
    local lib_dir="$HOME/.local/lib/claude-desktop"
    echo "default  (config: ${XDG_CONFIG_HOME:-$HOME/.config}/Claude)"
    if [[ ! -d "$lib_dir" ]]; then
        return 0
    fi
    local prefix="${APP_ID}-"
    local found=0
    for link in "$lib_dir"/${prefix}*; do
        [[ -L "$link" || -f "$link" ]] || continue
        local base="${link##*/}"
        local name="${base#$prefix}"
        # Skip stray entries that don't match our naming
        [[ "$name" =~ ^[a-zA-Z0-9_-]+$ ]] || continue
        echo "$name  (config: ${XDG_CONFIG_HOME:-$HOME/.config}/Claude-${name})"
        found=1
    done
    if (( found == 0 )); then
        echo "(no named profiles installed; create one with --create-profile=NAME)"
    fi
}

_diagnose() {
    echo '=== claude-desktop --diagnose ==='
    echo
    echo '--- Session ---'
    echo "XDG_SESSION_TYPE = ${XDG_SESSION_TYPE:-(unset)}"
    echo "XDG_CURRENT_DESKTOP = ${XDG_CURRENT_DESKTOP:-(unset)}"
    if [[ "${CLAUDE_NATIVE_TITLEBAR:-}" == '1' ]]; then
        echo "Titlebar = native (CLAUDE_NATIVE_TITLEBAR=1)"
    else
        echo "Titlebar = integrated (default)"
    fi
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
    if [[ -n "${XDG_RUNTIME_DIR:-}" && -S "${XDG_RUNTIME_DIR}/systemd/private" ]]; then
        echo "systemd user socket = ${XDG_RUNTIME_DIR}/systemd/private (present)"
    else
        echo "systemd user socket = (missing or unreachable; scope wrap will be skipped)"
    fi
    echo "gsettings = $(command -v gsettings || echo '(missing)')"
    echo "gdbus = $(command -v gdbus || echo '(missing)')"
    echo
    echo '--- App identity ---'
    echo "APP_ID = $APP_ID"
    echo "CLAUDE_PROFILE = ${CLAUDE_PROFILE:-(unset → default)}"
    echo "config_dir = $config_dir"
    echo "DESKTOP_ID = $DESKTOP_ID"
    # The system-installed default .desktop is the portal-identity anchor that
    # the systemd scope (app-claude-...scope) resolves back to. It is always the
    # default "claude-desktop.desktop" (issue #148); named-profile .desktop files
    # live user-local under ~/.local/share/applications/claude-desktop-<name>.desktop.
    local desktop_file="/usr/share/applications/claude-desktop.desktop"
    if [[ -f $desktop_file ]]; then
        echo ".desktop file: $desktop_file (found)"
    else
        echo ".desktop file: $desktop_file (MISSING - portal identity will fail)"
    fi
    if [[ -n "${CLAUDE_APPIMAGE_PATH:-}" ]]; then
        echo "CLAUDE_APPIMAGE_PATH = $CLAUDE_APPIMAGE_PATH"
        if [[ -f "$_APPIMAGE_DESKTOP_FILE" ]]; then
            local _ai_exec
            _ai_exec=$(grep '^Exec=' "$_APPIMAGE_DESKTOP_FILE" 2>/dev/null | head -1)
            echo "AppImage .desktop: $_APPIMAGE_DESKTOP_FILE (found)"
            echo "  Exec = $_ai_exec"
            if [[ "$_ai_exec" == *"$CLAUDE_APPIMAGE_PATH"* ]]; then
                echo "  Status: UP TO DATE"
            else
                echo "  Status: STALE (path mismatch)"
            fi
        else
            echo "AppImage .desktop: $_APPIMAGE_DESKTOP_FILE (MISSING - run --integrate)"
        fi
        if command -v xdg-mime &>/dev/null; then
            local _handler
            _handler=$(xdg-mime query default x-scheme-handler/claude 2>/dev/null || echo '(not set)')
            echo "claude:// handler = $_handler"
        fi
    else
        echo "CLAUDE_APPIMAGE_PATH = (unset - not an AppImage)"
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
    echo '--- Cowork VM capability (replicates the app probe) ---'
    # Mirrors the native Cowork backend's capability probe. If any of qemuPath /
    # firmwarePath / virtiofsdPath / kvm is missing, the app reports "VM not
    # supported" and the workspace Download does nothing. The resource base is
    # our fix_locale_paths layout: <app.asar dir>/locales.
    local _res_base
    _res_base="$(dirname "$APP_ASAR")/locales"
    local _arch _qemu_bin
    case "$(uname -m)" in
        aarch64|arm64) _arch=arm64; _qemu_bin=qemu-system-aarch64 ;;
        *)             _arch=x64;   _qemu_bin=qemu-system-x86_64 ;;
    esac
    echo "PATH (as diagnose sees it) = ${PATH:-(empty!)}"
    # qemuPath: first on PATH that is executable
    local _qemu_path=''
    if command -v "$_qemu_bin" &>/dev/null; then _qemu_path="$(command -v "$_qemu_bin")"; fi
    echo "qemuPath = ${_qemu_path:-NOT FOUND on PATH ($_qemu_bin)}"
    # firmwarePath: first readable OVMF/AAVMF CODE candidate (must match app's boi list)
    local _fw='' _c
    local _fw_candidates
    if [[ $_arch == arm64 ]]; then
        _fw_candidates=(/usr/share/AAVMF/AAVMF_CODE.fd)
    else
        _fw_candidates=(/usr/share/edk2/ovmf/OVMF_CODE.fd /usr/share/edk2/x64/OVMF_CODE.4m.fd /usr/share/edk2/x64/OVMF_CODE.fd /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd)
    fi
    for _c in "${_fw_candidates[@]}"; do
        if [[ -r $_c ]]; then _fw="$_c"; break; fi
    done
    echo "firmwarePath = ${_fw:-NOT FOUND (install edk2-ovmf / ovmf)}"
    if [[ -n $_fw ]]; then
        local _vars="${_fw/OVMF_CODE/OVMF_VARS}"; _vars="${_vars/AAVMF_CODE/AAVMF_VARS}"
        echo "  -> derived VARS = $_vars ($([[ -r $_vars ]] && echo present || echo MISSING))"
    fi
    # virtiofsdPath: system candidates, else bundled
    local _vfs=''
    for _c in /usr/libexec/virtiofsd /usr/lib/virtiofsd /usr/lib/qemu/virtiofsd /usr/bin/virtiofsd "$_res_base/virtiofsd"; do
        if [[ -r $_c ]]; then _vfs="$_c"; break; fi
    done
    echo "virtiofsdPath = ${_vfs:-NOT FOUND}"
    # helper + smol image (our resources/locales layout)
    echo "helperBinaryPath = $([[ -x $_res_base/cowork-linux-helper ]] && echo "$_res_base/cowork-linux-helper" || echo MISSING)"
    echo "smolBinPath = $([[ -r $_res_base/smol-bin.$_arch.img ]] && echo "$_res_base/smol-bin.$_arch.img" || echo MISSING)"
    # kvm + vsock (app checks R_OK|W_OK)
    echo "/dev/kvm = $([[ -r /dev/kvm && -w /dev/kvm ]] && echo ok || { [[ -e /dev/kvm ]] && echo 'NO PERMISSION (add user to kvm group + relogin)' || echo 'MISSING (enable virtualization in BIOS)'; })"
    echo "/dev/vhost-vsock = $([[ -r /dev/vhost-vsock && -w /dev/vhost-vsock ]] && echo ok || { [[ -e /dev/vhost-vsock ]] && echo 'NO PERMISSION' || echo 'MISSING (sudo modprobe vhost_vsock)'; })"
    if [[ -n $_qemu_path && -n $_fw && -n $_vfs && -r /dev/kvm && -w /dev/kvm && -r /dev/vhost-vsock && -w /dev/vhost-vsock ]]; then
        echo "=> capability probe SHOULD pass (Cowork supported)"
    else
        echo "=> capability probe WOULD FAIL - fix the NOT-FOUND/MISSING item(s) above"
    fi
    echo
    echo '--- Recent launcher log (last 10 lines) ---'
    local logf="${XDG_CACHE_HOME:-$HOME/.cache}/claude-desktop/launcher.log"
    if [[ -f $logf || -f $logf.old ]]; then
        # Read across the rotated backup so the last 10 lines survive a
        # rotation that just happened at startup. cat exits non-zero when one
        # of the files is missing (no .old before the first rotation) - under
        # set -euo pipefail that would abort --diagnose, hence the || true.
        cat "$logf.old" "$logf" 2>/dev/null | tail -10 || true
    else
        echo '(no launcher.log yet)'
    fi
}

# ---------------------------------------------------------------------------
# Per-profile binary maintenance (runs once per launch, named profiles only)
# ---------------------------------------------------------------------------

# Auto-heal stale per-profile installs after package upgrades or NixOS rebuilds.
# Also refresh ELECTRON_BIN if path discovery had to fall back to the canonical
# (e.g. dangling per-profile from a moved Nix store path) — we want the next
# launch step to use the freshly materialised per-profile binary so WM_CLASS /
# Wayland app_id reflect the profile.
if [[ -n "$profile_suffix" ]]; then
    _refresh_profile_binary_if_stale || true
    _profile_bin="$HOME/.local/lib/claude-desktop/${APP_ID}${profile_suffix}"
    if [[ -x "$_profile_bin" && "$ELECTRON_BIN" != "$_profile_bin" ]]; then
        ELECTRON_BIN="$_profile_bin"
    fi

    # Silent-degradation hint: --profile=NAME isolates state but the
    # WM_CLASS / Wayland app_id stays as the default unless --create-profile
    # has materialised a per-profile binary. Most users will want both.
    # Suppress with CLAUDE_PROFILE_QUIET=1.
    if [[ ! -e "$_profile_bin" && -z "${CLAUDE_PROFILE_QUIET:-}" ]]; then
        echo >&2 "claude-desktop: profile '$CLAUDE_PROFILE' has isolated state but no per-profile WM identity."
        echo >&2 "  Windows will share the default profile's taskbar entry. To fix:"
        echo >&2 "    claude-desktop --create-profile=$CLAUDE_PROFILE"
        echo >&2 "  (suppress this message with CLAUDE_PROFILE_QUIET=1)"
    fi
fi

# ---------------------------------------------------------------------------
# AppImage auto-integration (protocol handler + menu entry)
# ---------------------------------------------------------------------------
if [[ -n "${CLAUDE_APPIMAGE_PATH:-}" ]]; then
    _appimage_integrate quiet || true
fi

case "${1:-}" in
    --help|-h)
        cat <<'HELP'
Usage: claude-desktop [OPTION]

Launch Claude Desktop, or run a subcommand.

Options:
  --toggle                  Toggle Quick Entry overlay (~5-25 ms via Unix
                            socket when app is running; launches app on cold
                            start). Bind this to a global keyboard shortcut.
  --toggle-quick-entry      Alias for --toggle (backward-compatible).
  --install-gnome-hotkey [ACCEL]
                            Install a GNOME custom keybinding for Quick Entry.
                            Default accelerator: <Primary><Alt>space
                            Example: claude-desktop --install-gnome-hotkey '<Super>space'
  --uninstall-gnome-hotkey  Remove the GNOME custom keybinding.
  --diagnose                Print session type, Electron version, portal status,
                            GNOME hotkey slot, and recent launcher log. Paste
                            output into issue reports.
  --profile=NAME            Launch (or target subcommand at) a named profile.
                            Each profile has its own login, logs, and Claude
                            Code config. Can also be selected by invoking via
                            a 'claude-desktop-NAME' symlink. Omit for default.
  --create-profile=NAME     Create profile NAME: installs user-local symlinks
                            (~/.local/bin/claude-desktop-NAME, ~/.local/lib/...)
                            and a .desktop file with a per-profile WMClass so
                            the window manager treats it as a separate app.
                            User data is not created until first launch.
  --delete-profile=NAME     Remove the entry points for profile NAME. User data
                            (~/.config/Claude-NAME, ~/.claude-NAME) is preserved.
  --list-profiles           List installed profiles.
  --integrate               Register the claude:// protocol handler and add an
                            application menu entry (AppImage only). Happens
                            automatically on every launch; use this to force
                            registration or verify the current state.
  --unintegrate             Remove the AppImage protocol handler registration
                            and menu entry. Does not affect system packages.
  --native-titlebar          Restore the native window frame instead of the
                            integrated (overlay) titlebar. Same as setting
                            CLAUDE_NATIVE_TITLEBAR=1.
  --no-systemd-scope        Skip the systemd --user --scope wrapper for this
                            launch. Use in sandboxes (bwrap, distrobox, ...)
                            where the systemd private socket is unreachable.
                            Same as setting CLAUDE_DISABLE_SYSTEMD_SCOPE=1.
  --help, -h                Show this help message.

Environment variables:
  CLAUDE_PROFILE=NAME       Same effect as --profile=NAME. Inherited by Electron
                            and the Claude Code child process so per-profile
                            sockets and config dirs are picked up automatically.
  CLAUDE_NATIVE_TITLEBAR=1  Restore the native window frame (same as --native-titlebar).
  CLAUDE_USE_XWAYLAND=1     Force XWayland instead of native Wayland.
  CLAUDE_MENU_BAR=visible   Menu bar mode: auto (default), visible, hidden.
  CLAUDE_DISABLE_GPU=1      Disable GPU compositing (white screen fix).
  CLAUDE_DISABLE_GPU=full   Disable GPU entirely (more aggressive fallback).
  CLAUDE_ELECTRON=PATH      Override path to Electron binary.
  CLAUDE_APP_ASAR=PATH      Override path to app.asar.
  CLAUDE_DISABLE_SYSTEMD_SCOPE=1
                            Skip the systemd --user --scope wrapper (for
                            sandboxes without access to the systemd private
                            socket; portal app identity may not resolve).
  CLAUDE_APPIMAGE_PATH=PATH Set by AppRun when running as AppImage. Used for
                            protocol handler registration. Do not set manually
                            unless running from --appimage-extract.

All other arguments are passed through to Electron.
HELP
        exit 0
        ;;
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
    --create-profile=*)
        _create_profile "${1#--create-profile=}"
        exit $?
        ;;
    --create-profile)
        shift
        _create_profile "${1:-}"
        exit $?
        ;;
    --delete-profile=*)
        _delete_profile "${1#--delete-profile=}"
        exit $?
        ;;
    --delete-profile)
        shift
        _delete_profile "${1:-}"
        exit $?
        ;;
    --list-profiles)
        _list_profiles
        exit 0
        ;;
    --integrate)
        _appimage_integrate
        exit $?
        ;;
    --unintegrate)
        _appimage_unintegrate
        exit $?
        ;;
    --toggle|--toggle-quick-entry)
        # Fast Quick Entry toggle via Unix domain socket (~5-25 ms).
        # Falls through to Electron if socket unavailable (cold start).
        # --toggle-quick-entry is the original flag; --toggle is the short alias.
        _SOCK="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/claude-desktop-qe${profile_suffix}.sock"
        if [ -S "$_SOCK" ]; then
            if command -v socat >/dev/null 2>&1; then
                socat /dev/null "UNIX-CLIENT:$_SOCK" 2>/dev/null && exit 0
            fi
            if command -v python3 >/dev/null 2>&1; then
                python3 -c "import socket,sys;s=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM);s.settimeout(0.5);s.connect(sys.argv[1]);s.close()" "$_SOCK" 2>/dev/null && exit 0
            fi
            echo "[launcher] socket exists but no client (socat/python3) found — falling back to Electron" >&2
        fi
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

# Titlebar mode: integrated (default) vs native (opt-out).
# In native mode, disable Chromium's CustomTitlebar feature so Electron
# renders the system frame. In integrated mode, keep it enabled so
# titleBarOverlay works.
if [[ "${CLAUDE_NATIVE_TITLEBAR:-}" == '1' ]]; then
    ELECTRON_ARGS+=('--disable-features=CustomTitlebar')
    log 'Titlebar: native (CLAUDE_NATIVE_TITLEBAR=1)'
else
    log 'Titlebar: integrated (default)'
fi

# Force ARGB visuals so `transparent:true` popups (Quick Entry) render their
# outer window transparently on compositors that wouldn't otherwise expose
# alpha. No-op on X11 when already supported. Fixes the "opaque rectangle
# behind the rounded card" symptom (issue #39) on most Wayland configs.
ELECTRON_ARGS+=('--enable-transparent-visuals')

case $platform_mode in
    x11)
        log 'X11 session detected'
        if [[ -n "${CLAUDE_APPIMAGE_PATH:-}" ]]; then
            log 'AppImage X11: adding --no-sandbox (FUSE cannot carry SUID)'
            ELECTRON_ARGS+=('--no-sandbox')
        fi
        ;;
    xwayland)
        log 'Using X11 backend via XWayland (CLAUDE_USE_XWAYLAND=1)'
        ELECTRON_ARGS+=('--no-sandbox' '--ozone-platform=x11')
        ;;
    wayland)
        log 'Using native Wayland backend'
        ELECTRON_ARGS+=('--no-sandbox')
        if [[ "${CLAUDE_NATIVE_TITLEBAR:-}" == '1' ]]; then
            ELECTRON_ARGS+=('--enable-features=UseOzonePlatform,WaylandWindowDecorations,GlobalShortcutsPortal')
        else
            ELECTRON_ARGS+=('--enable-features=UseOzonePlatform,GlobalShortcutsPortal')
        fi
        ELECTRON_ARGS+=('--ozone-platform=wayland')
        ELECTRON_ARGS+=('--enable-wayland-ime')
        ELECTRON_ARGS+=('--wayland-text-input-version=3')
        # On GPUs where Chromium (Electron 42) brings up Vulkan - real Intel/AMD/
        # NVIDIA with a recent Mesa driver - it refuses to pair Vulkan with
        # --ozone-platform=wayland: the Wayland surface factory fails and NO window
        # is ever created (silent no-UI startup, seen on Ubuntu/GNOME Wayland).
        # Machines where Chromium never selects Vulkan (VMs, software GL) don't hit
        # this, and disabling the feature there is a harmless no-op. Chromium refuses
        # Vulkan+Wayland outright, so this removes no working render path. x11/
        # xwayland use --ozone-platform=x11 and keep Vulkan. Opt out: CLAUDE_ENABLE_VULKAN=1.
        # log line: wayland_surface_factory.cc "'--ozone-platform=wayland' is not compatible with Vulkan"
        if [[ "${CLAUDE_ENABLE_VULKAN:-}" != '1' ]]; then
            ELECTRON_ARGS+=('--disable-features=Vulkan')
            log 'Vulkan disabled for Wayland surface compatibility (set CLAUDE_ENABLE_VULKAN=1 to keep it)'
        else
            log 'Vulkan kept on Wayland (CLAUDE_ENABLE_VULKAN=1)'
        fi
        ;;
esac

# Now that platform_mode and electron_major are known, service the --diagnose
# subcommand if requested. Exits here — does not launch Electron.
if [[ -n ${_diagnose_requested:-} ]]; then
    echo "platform_mode = $platform_mode"
    echo "electron_major = $electron_major"
    # Note: CLAUDE_DISABLE_GPU flags are appended after this point, so they are
    # not reflected here; the platform/Vulkan/titlebar flags are.
    echo "electron_args = ${ELECTRON_ARGS[*]}"
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

# In native titlebar mode, tell Electron to use the system frame.
# In integrated mode (default), do NOT set this so titleBarOverlay works.
if [[ "${CLAUDE_NATIVE_TITLEBAR:-}" == '1' ]]; then
    export ELECTRON_USE_SYSTEM_TITLE_BAR=1
fi

# Pass through CLAUDE_NATIVE_TITLEBAR if set (env var, not just --flag)
if [[ -n "${CLAUDE_NATIVE_TITLEBAR:-}" ]]; then
    export CLAUDE_NATIVE_TITLEBAR
fi

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

lock_file="$config_dir/SingletonLock"

# When a profile is active, redirect Electron's userData away from the default
# ~/.config/Claude. This is what isolates SingletonLock, logins, logs, etc.
# For the default profile, omit the flag so behavior is byte-identical to v1.
if [[ -n "$profile_suffix" ]]; then
    mkdir -p "$config_dir"
    ELECTRON_ARGS+=("--user-data-dir=$config_dir")
fi

if [[ -L "$lock_file" ]]; then
    lock_target="$(readlink "$lock_file" 2>/dev/null)" || true
    lock_pid="${lock_target##*-}"
    if [[ "$lock_pid" =~ ^[0-9]+$ ]] && ! kill -0 "$lock_pid" 2>/dev/null; then
        rm -f "$lock_file"
        log "Removed stale SingletonLock (PID $lock_pid no longer running)"
    fi
fi

# ---------------------------------------------------------------------------
# Launch
# ---------------------------------------------------------------------------

log "Launching: $ELECTRON_BIN $APP_ASAR ${ELECTRON_ARGS[*]} $*"

# Launch inside a named systemd user scope. The scope name (cgroup,
# app-${DESKTOP_ID}-PID.scope) is the identity signal xdg-desktop-portal uses to
# resolve us back to our .desktop. By the freedesktop convention the middle
# token is the application id == .desktop basename, so it must be DESKTOP_ID
# ("claude-desktop"), NOT APP_ID ("claude") - otherwise the portal would look
# for the now-renamed "claude.desktop" and fail to identify us (issue #148).
# This is separate from the window app_id / X11 WM_CLASS ("claude-desktop", from
# the app's desktopName); that dock-icon match uses StartupWMClass / the .desktop
# filename instead. APP_ID remains only the cosmetic Electron binary basename.
# Fall back to direct exec in environments without user systemd (rare).
# Three gates: explicit opt-out, binary present, runtime dir set, and the
# user-systemd private socket actually reachable. The last check matters in
# sandboxes (bwrap, distrobox, some container setups) where `systemd-run`
# exists but the socket is filtered: without the probe we would `exec` into
# systemd-run and die there, with no fallback. See issue #89.
# Guarantee a usable PATH inside the Electron process. When Claude is launched
# from a .desktop file (GNOME/XFCE/KDE menu), the systemd --user scope can start
# with an EMPTY PATH - the display-manager-spawned graphical session and the
# systemd user manager often carry no PATH. That breaks any feature that resolves
# a binary via $PATH; in particular the native Cowork VM backend probes for
# `qemu-system-x86_64` by walking process.env.PATH, so an empty PATH makes Cowork
# report "VM not supported" and the workspace Download button do nothing - even
# though qemu is installed. (Terminal launches are unaffected: they inherit the
# shell's PATH.) We therefore export an explicit PATH that always includes the
# standard system bindirs (where qemu/virtiofsd live), appended to whatever the
# launcher inherited, and propagate it into the scope with --setenv.
_claude_path="${PATH:-}"
for _d in /usr/local/bin /usr/bin /bin /usr/local/sbin /usr/sbin /sbin; do
    case ":${_claude_path}:" in
        *":${_d}:"*) : ;;                       # already present
        *) _claude_path="${_claude_path:+${_claude_path}:}${_d}" ;;
    esac
done
export PATH="$_claude_path"

if [[ "${CLAUDE_DISABLE_SYSTEMD_SCOPE:-}" != '1' ]] \
    && command -v systemd-run &>/dev/null \
    && [[ -n "${XDG_RUNTIME_DIR:-}" ]] \
    && [[ -S "${XDG_RUNTIME_DIR}/systemd/private" ]]; then
    exec systemd-run --user --scope --quiet \
        --unit="app-${DESKTOP_ID}-$$.scope" \
        --description='Claude Desktop' \
        --setenv="PATH=${_claude_path}" \
        -- "$ELECTRON_BIN" "$APP_ASAR" "${ELECTRON_ARGS[@]}" "$@"
fi
log 'systemd user scope unavailable (binary missing, socket unreachable, or CLAUDE_DISABLE_SYSTEMD_SCOPE=1): launching without scope; xdg-desktop-portal may fail to identify the app'
exec "$ELECTRON_BIN" "$APP_ASAR" "${ELECTRON_ARGS[@]}" "$@"
