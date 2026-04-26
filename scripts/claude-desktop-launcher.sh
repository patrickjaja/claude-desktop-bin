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

# Strip --profile=<name> / --profile <name> from argv before subcommand
# dispatch and Electron pass-through.
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
                # Re-exec under the routed profile. The exec replaces this
                # process so we don't need any further cleanup. The receiving
                # profile will see the URL via its second-instance handler
                # (or as initial argv if it isn't running yet).
                exec "$0" "--profile=$_routed_profile" "$@"
            fi
        fi
    fi
fi

# ---------------------------------------------------------------------------
# Path discovery (supports Arch, RPM, DEB, AppImage layouts)
# ---------------------------------------------------------------------------

ELECTRON_BIN="${CLAUDE_ELECTRON:-}"
APP_ASAR="${CLAUDE_APP_ASAR:-}"

# The bundled Electron binary must be named after APP_ID so Wayland app_id /
# X11 WM_CLASS match our .desktop file. Electron ignores Chromium's --class
# flag and derives the window identity from the binary name instead. We
# prefer the renamed binary; fall back to `electron` for mid-upgrade installs.
#
# When a profile is active, prefer the user-local symlink at
# ~/.local/lib/claude-desktop/<APP_ID>-<profile> created by --create-profile.
# That path's basename gives Wayland/X11 a per-profile WM_CLASS, so the window
# manager treats it as a separate app (separate icon, separate Alt-Tab group).
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
    echo "$HOME/.local/share/applications/${APP_ID}-${name}.desktop"
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
    local desktop_file="$HOME/.local/share/applications/${APP_ID}-${name}.desktop"

    if [[ -e "$electron_bin_path" || -e "$launcher_link" || -e "$desktop_file" ]]; then
        echo >&2 "claude-desktop: profile '$name' already exists. Use --delete-profile=$name first to recreate."
        return 1
    fi

    mkdir -p "$(dirname "$electron_bin_path")" "$(dirname "$launcher_link")" "$(dirname "$desktop_file")"

    # The per-profile Electron binary must be a real file (not a symlink) so
    # /proc/self/exe resolves to the per-profile path. Electron derives Wayland
    # app_id from its own /proc/self/exe basename; without a distinct binary
    # the WM groups all profiles as one app. This is how Chrome itself does
    # multi-channel (google-chrome-stable / google-chrome-beta are real copies).
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

    # Try to find an existing system .desktop to inherit Icon=, etc.
    local source_desktop=""
    for c in \
        "/usr/share/applications/${APP_ID}.desktop" \
        "$HOME/.local/share/applications/${APP_ID}.desktop"; do
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
        # Rewrite Name, Exec, StartupWMClass; drop MimeType= so the
        # claude:// scheme remains owned by the system .desktop. The launcher
        # routes incoming URLs to the right profile via the auth marker; if
        # named profiles also claimed the scheme, xdg-mime ordering would
        # short-circuit our routing for whichever entry got picked first.
        awk -v name="$name" -v appid="$APP_ID" -v execline="$exec_line" '
            BEGIN { FS=OFS="=" }
            /^Name=/           { print "Name=Claude (" name ")"; next }
            /^Exec=/           { print execline; next }
            /^StartupWMClass=/ { print "StartupWMClass=" appid "-" name; next }
            /^MimeType=/       { next }
            { print }
        ' "$source_desktop" > "$desktop_file"
    else
        cat > "$desktop_file" <<EOF
[Desktop Entry]
Name=Claude ($name)
${exec_line}
Terminal=false
Type=Application
Icon=${APP_ID}
StartupWMClass=${APP_ID}-${name}
Categories=Network;InstantMessaging;
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
    local desktop_file="$HOME/.local/share/applications/${APP_ID}-${name}.desktop"

    local removed=0
    for f in "$electron_link" "$launcher_link" "$desktop_file"; do
        if [[ -L "$f" || -f "$f" ]]; then
            rm -f "$f"
            echo "Removed: $f"
            ((removed++))
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
    echo "CLAUDE_PROFILE = ${CLAUDE_PROFILE:-(unset → default)}"
    echo "config_dir = $config_dir"
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
  --help, -h                Show this help message.

Environment variables:
  CLAUDE_PROFILE=NAME       Same effect as --profile=NAME. Inherited by Electron
                            and the Claude Code child process so per-profile
                            sockets and config dirs are picked up automatically.
  CLAUDE_USE_XWAYLAND=1     Force XWayland instead of native Wayland.
  CLAUDE_MENU_BAR=visible   Menu bar mode: auto (default), visible, hidden.
  CLAUDE_DISABLE_GPU=1      Disable GPU compositing (white screen fix).
  CLAUDE_DISABLE_GPU=full   Disable GPU entirely (more aggressive fallback).
  CLAUDE_ELECTRON=PATH      Override path to Electron binary.
  CLAUDE_APP_ASAR=PATH      Override path to app.asar.

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

config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/Claude${profile_suffix}"
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
        --unit="app-${APP_ID}${profile_suffix}-$$.scope" \
        --description='Claude Desktop' \
        -- "$ELECTRON_BIN" "$APP_ASAR" "${ELECTRON_ARGS[@]}" "$@"
fi
log 'systemd-run unavailable — launching without scope; xdg-desktop-portal may fail to identify the app'
exec "$ELECTRON_BIN" "$APP_ASAR" "${ELECTRON_ARGS[@]}" "$@"
