---
name: linux
description: Linux compatibility reference for the claude-desktop-bin project (patching the upstream Claude Desktop msix for Linux). Use when working on Linux support, session managers, distros, Computer Use input/screenshot backends, glibc floors, Wayland/X11, multi-profile, or any patch in patches/*.nim. Loads the distro/session matrix, the input + screenshot cascades, native-binary glibc floors, and known Linux gotchas.
when_to_use: When the user mentions Linux compatibility, X11, Wayland, wlroots, GNOME, KDE, XWayland, a distro (Arch/Ubuntu/Debian/Fedora/RHEL/NixOS/Jetson), xdotool/ydotool/grim/spectacle, glibc, node-pty, kwin-portal-bridge, app_id/WM_CLASS, profiles, or edits files under patches/ or scripts/.
paths: patches/**, scripts/**, js/**, baseline/PLATFORM_GATE_BASELINE.md, wayland.md
---

# Linux compatibility — claude-desktop-bin

Patches a remotely-managed upstream `Claude.msix` (Windows Electron app) to run on Linux. **Linux only** — never add macOS/Windows code. Minified JS identifiers change every upstream release, so patterns must use `[\w$]+` wildcards anchored on stable strings (feature names, log messages, `process.platform==="darwin"`). For a clean unpatched bundle to test patterns against, see `/fresh-upstream`.

## Support matrix (must validate every change against ALL rows)

| Session | Compositors/DEs | Input backend | Screenshot |
|---|---|---|---|
| X11 | any (GNOME, KDE, i3, …) | `xdotool` | `gnome-screenshot` → `scrot` → `import` (ImageMagick) |
| Wayland wlroots | Sway, Hyprland | `ydotool` (+`ydotoold`) | `grim` |
| Wayland GNOME | GNOME Shell | `ydotool` (+`ydotoold`) | portal+pipewire → `gnome-screenshot` → `gdbus` |
| Wayland KDE | KDE Plasma | `ydotool` (+`ydotoold`) | `spectacle` (`kwin-portal-bridge` bundled fallback) |
| XWayland | any Wayland | `xdotool` (fallback) | depends on compositor |

| Distro | Pkg | Min glibc | Arch |
|---|---|---|---|
| Arch | AUR | 2.41 | x86_64, aarch64 |
| Ubuntu 22.04+ | deb | 2.35 | amd64, arm64 |
| Debian 11+ | deb | 2.31 | amd64, arm64 |
| Fedora 40+ | rpm | 2.39 | x86_64, aarch64 |
| RHEL 9+ | rpm | 2.34 | x86_64, aarch64 |
| NixOS | flake | 2.40 | x86_64, aarch64 |
| Jetson (JetPack 6) | deb | 2.35 | aarch64 |
| Any (glibc) | AppImage | varies | x86_64, aarch64 |

## Session detection (`scripts/claude-desktop-launcher.sh`)
- `is_wayland=true` iff `$WAYLAND_DISPLAY` set; else X11. Both unset → hard error.
- `platform_mode ∈ {x11, wayland, xwayland}` drives Electron flags. `CLAUDE_USE_XWAYLAND=1` forces xwayland (escape hatch). **Niri ignores it** (no XWayland) → stays wayland.
- Electron <40 on Wayland warns loudly: broken GlobalShortcutsPortal (electron/electron#49806) → global hotkeys only work when focused. Fix: update Electron, or `CLAUDE_USE_XWAYLAND=1`.
- `claude-desktop --diagnose` dumps `XDG_SESSION_TYPE`, `WAYLAND_DISPLAY`, `platform_mode`, electron major.

## Input + screenshot executors — single source of truth
The cascade logic lives in checked-in JS under `js/`, embedded into `patches/fix_computer_use_linux.nim` via `staticRead` (35 sub-patches, PCRE/`std/nre` for backreferences). **Edit the `.js`, not the patch.**
- `js/cu_linux_executor.js` — inline executor: detection, all screenshot/input cascades, `[claude-cu] diagnostics:` lines.
- `js/executor_linux.js` — KWin/KDE hybrid executor.
- `js/cu_handler_injection.js`, `js/cu_mode_preamble.js` — handler wiring + mode preamble.

**Input:** `_checkYdotool()` → true only if `ydotool` present AND (`pgrep -x ydotoold` OR `$YDOTOOL_SOCKET`/`$XDG_RUNTIME_DIR/.ydotool_socket` exists). On Wayland use `ydotool`, else fall back to `xdotool` (via XWayland). xdotool cannot inject on native Wayland — daemon is mandatory there.
**Screenshot order (in code):** `COWORK_SCREENSHOT_CMD` (override) → grim (wlroots) → portal+pipewire (GNOME, restore-token) → gnome-screenshot+convert (GNOME) → gdbus (GNOME Shell DBus) → portal+pipewire (GNOME first-run) → spectacle (KDE) → gnome-screenshot (X11) → scrot (X11) → import/ImageMagick (X11) → Electron `desktopCapturer` (last resort).

**`[claude-cu] diagnostics:`** lines print to stderr/stdout at startup/first-use: `input-backend=ydotool|xdotool`, `screenshot: captured via <tool>`, missing-tool warnings, VM/Wayland detection. **Always ask users to paste these when debugging Computer Use.**

## Native binaries & glibc floors (CI enforces via `objdump -T | grep GLIBC_`)
| Binary | Floor | Why | CI base |
|---|---|---|---|
| node-pty | 2.31 (Debian 11) | must run on all distros | `node:20-bullseye` |
| kwin-portal-bridge | 2.39 (Ubuntu Noble) | KWin 6.6+ only on Noble+/Fedora 40+ | `ubuntu:noble` + native cross |

- node-pty rebuilt for Linux + cross-compiled x86_64→arm64 via `scripts/rebuild-pty-for-arch.sh` (Docker + QEMU binfmt; rebuilds `pty.node` + `spawn-helper`; verifies ELF arch). Broken `pty.node` = terminal/cowork spawn fails.
- New native binary → pick floor = its minimum viable distro; bump `.electron-shasums` workflow if Electron pinning involved.

## Multi-profile / window identity (`scripts/claude-desktop-launcher.sh`)
- Per-profile Electron binary at `~/.local/lib/claude-desktop/<APP_ID>-<name>` via **hardlink → reflink → copy** (never symlink — Electron derives identity from `realpath(/proc/self/exe)`, kernel resolves symlinks first).
- WM_CLASS = Wayland app_id = binary basename (`claude` default, `claude-<name>` per profile). systemd scope `app-claude(-<name>)-$$.scope`.
- Per-profile isolation: `--user-data-dir` (Electron userData), `CLAUDE_CONFIG_DIR` (Claude Code CLI), `CLAUDE_PROFILE` env (sockets/markers). See CLAUDE.md "Profile System" table.
- **Portal identity caveat** (`project_platform_gate_baseline` / portal memory): xdg-desktop-portal wants a reverse-URL app_id to route activations back to unsandboxed Electron; shipping single-segment `"Claude"` breaks routing across compositors. Fix is launcher-only.

## Known Linux gotchas (one line each → which patch)
- EXDEV cross-device rename (/tmp tmpfs ↔ ~/.config) → `fix_cross_device_rename.nim` (copy+unlink fallback).
- Sandbox credential-path blocklist (.ssh/.gnupg/.aws/keyrings/.pki/autostart) → `fix_sensitive_dirs_linux.nim`.
- Tray DBus races on session change → `fix_tray_dbus.nim` (async + mutex + destroy delay). Theme: `fix_tray_icon_theme.nim`.
- GNOME Mutter focus-stealing: Quick Entry opens then self-dismisses → `fix_quick_entry_wayland_blur_guard.nim` (ignore blur with no preceding focus). KDE/Hyprland transfer focus so click-outside works; GNOME users close with Esc.
- Native titlebar overlay was win32-only → `fix_native_frame.nim` (+ `_renderer`); gate via `CLAUDE_NATIVE_TITLEBAR`.
- Locale/ICU paths not portable → `fix_locale_paths.nim` (runtime `dirname(getAppPath())+"/locales"`).
- `process.argv` undefined in renderer broke Claude Code web bundle → `fix_process_argv_renderer.nim`.
- CliGovernor false memory-pressure (uses .free, not MemAvailable) evicts sessions → `fix_cli_governor_memavailable.nim` (reads /proc/meminfo).
- Node host bound 0.0.0.0 → `fix_0_node_host.nim` (127.0.0.1).
- `app.dock.bounce` (macOS) → `fix_dock_bounce.nim` (stub).

## wayland.md highlights
- GNOME hotkey: GlobalShortcuts portal approval easy to miss (Electron returns true even if it failed). Workaround `claude-desktop --install-gnome-hotkey` writes a gsettings custom keybinding (bypasses portal), toggling via Unix socket in `$XDG_RUNTIME_DIR`.
- KDE stale kglobalaccel entries after crash block re-registration → `gdbus` unregister before re-register.

## Rules
1. Every change must work across all 5 session types and all distro/arch rows — think through each, especially Wayland fragmentation (GNOME ≠ KDE ≠ wlroots).
2. New input/screenshot work → edit `js/cu_linux_executor.js` (+ `executor_linux.js` for KDE), keep diagnostics lines.
3. Fixed user-level paths → prefer `app.getPath("userData")` (auto-isolates per profile) over `~/.config/Claude`.
4. New native module → builds for x86_64 AND aarch64, pick a glibc floor, CI verifies.
5. Verify JS syntax after any patch: `node --check ./tmp/app.asar.contents/.vite/build/index.js`.
