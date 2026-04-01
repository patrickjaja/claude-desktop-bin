# Changelog

All notable changes to claude-desktop-bin AUR package will be documented in this file.

## 2026-04-01 (v1.2.234) — Computer Use Wayland fix

### Fixed
- **fix_computer_use_linux.py**: Computer Use now works on all Wayland compositors (tested KDE Plasma + GNOME on Ubuntu). Three bugs fixed:
  1. **Window click-through** — Added `setIgnoreMouseEvents` wrapper so clicks pass through Claude's window to the target app.
  2. **Cursor positioning** — Split ydotool `--absolute` into origin-reset + delay + relative move (single-command was too fast for libinput).
  3. **Keyboard input** — `_mapKeyWayland()` returns raw Linux numeric keycodes. ydotool v1.0.4 `key` only accepts numeric codes, not names.

### Added
- **scripts/setup-ydotool.sh**: One-command setup for Ubuntu/Debian Wayland users. Builds ydotool v1.0.4 from source, configures uinput permissions, starts daemon. Also sets flat mouse acceleration on GNOME.
  Usage: `curl -fsSL https://raw.githubusercontent.com/patrickjaja/claude-desktop-bin/master/scripts/setup-ydotool.sh | sudo bash`

### Docs
- **README.md**: All Wayland compositors need ydotool for input (not just wlroots). Added ydotool setup section with `curl | sudo bash` for Ubuntu/Debian, one-liners for Arch/Fedora, and GNOME flat acceleration note.

### Changed
- **Version bump to v1.2.234** — Major upstream release. Feature flag registry unchanged (same 18 features), but internal function names renamed across the board.
- **fix_computer_use_linux.py**: Platform gate changed from inline `process.platform==="darwin"` to Set-based `ese = new Set(["darwin","win32"])` with `vee()` checker. Updated patch to add `"linux"` to the Set instead of removing individual gates. This single change fixes all computer-use platform checks (server push, chicagoEnabled, overlay init). handleToolCall regex updated for new code structure (Y5e opted-out block before dispatcher).
- **read_terminal MCP server**: Upstream now natively supports Linux (`LRe = isDarwin || isWin32 || isLinux`). **Removed `fix_read_terminal_linux.py`** — patch no longer needed.

### Upstream Changes
- **Computer use**: Platform gate now uses a Set (`ese`) gating `vee()` function, adding Windows support alongside macOS. Linux still requires our patch to add to the Set.
- **Terminal server**: Now natively supports Linux (variable `LRe` includes all three platforms).
- **Registration function renamed**: `Are()` → `One()` for internal MCP server registration.
- **Feature flag function renames**: Static registry `_b()` → `Uw()`, async merger `Cie` → `Lse`, production gate `fve()` → `I_e()`.
- **GrowthBook expansion**: 38+ flag IDs now in use (was ~33 in v1.1.9669). New flags for floatingAtoll state sync (`1985802636`).
- **Operon**: Static entry now unconditionally returns `{status:"unavailable"}` (`$gn()`). Async override introduces 5-second delay before GrowthBook check.

### Docs
- **CLAUDE_FEATURE_FLAGS.md**: Updated for v1.2.234 — new function names (`Uw`, `Lse`, `I_e`), same 18 features.
- **CLAUDE_BUILT_IN_MCP.md**: Updated for v1.2.234 — registration function `Are()` → `One()`, terminal server now natively supports Linux.

## 2026-04-01 (v1.1.9669)

### Changed
- **fix_computer_use_linux.py**: Replaced external clipboard tools (`xclip`, `xsel`, `wl-clipboard`) with Electron's built-in `clipboard` API. Clipboard read/write and type-via-clipboard now use `electron.clipboard.readText()`/`writeText()` directly — no external packages needed.
- **fix_computer_use_linux.py**: Replaced external display enumeration tools (`xrandr`, `wlr-randr`) with Electron's built-in `screen.getAllDisplays()` API for both X11 and Wayland. Eliminates 2 optional dependencies.
- **fix_computer_use_linux.py**: Added `desktopCapturer` + `nativeImage.crop()` as last-resort screenshot fallback before the error throw. Helps on exotic Wayland compositors where no CLI screenshot tool is available.
- **Packaging**: Removed `xclip`, `xsel`, `wl-clipboard`, `wlr-randr`, `xorg-xrandr` from optional dependencies across all formats (PKGBUILD, deb, rpm). 5 fewer packages to install.

### Fixed
- **fix_computer_use_linux.py**: Computer Use clicks now work on all Wayland compositors (KDE, GNOME, wlroots). Three bugs fixed:
  1. **Window hiding before actions** — Added `setIgnoreMouseEvents` wrapper (matching upstream macOS `lB()` behavior) so clicks pass through Claude Desktop's window to the target app behind it.
  2. **ydotool absolute positioning** — Split `mousemove --absolute X Y` into two commands with 50ms delay (origin reset + relative move). The single-command approach sent both events too fast for libinput to process correctly, causing the cursor to land at (0,0).
  3. **ydotool keyboard input** — `_mapKeyWayland()` now returns raw Linux numeric keycodes (e.g. 29 for Ctrl, 56 for Alt) instead of symbolic names. ydotool v1.0.4 `key` command parses names as `strtol()` = 0, silently dropping all key events.
- **fix_computer_use_linux.py**: Screenshot support on non-wlroots Wayland compositors (GNOME, KDE). New fallback chain: `COWORK_SCREENSHOT_CMD` env override → grim (wlroots) → GNOME Shell D-Bus `ScreenshotArea` → spectacle + crop (KDE) → gnome-screenshot → scrot → import. Fixes [claude-cowork-service#13](https://github.com/patrickjaja/claude-cowork-service/issues/13).
- **fix_computer_use_linux.py**: ydotool robustness — `_checkYdotool()` verifies ydotoold daemon is running before attempting ydotool commands. Falls back to xdotool via XWayland if daemon not found.

### Added
- **scripts/setup-ydotool.sh**: One-command ydotool v1.0.4 setup for Ubuntu/Debian Wayland users. Builds from source, configures uinput permissions, and creates a systemd service. Ubuntu/Debian ship ydotool 0.1.8 which has incompatible command syntax. Usage: `curl -fsSL https://raw.githubusercontent.com/patrickjaja/claude-desktop-bin/master/scripts/setup-ydotool.sh | sudo bash`

### Docs
- **README.md**: Fixed Computer Use dependencies — all Wayland compositors (KDE, GNOME, wlroots) require `ydotool` for input automation, not just wlroots. The `xdotool (XWayland)` fallback cannot click native Wayland windows.
- **README.md**: Added `ydotool setup` section with one-liner for Arch/Fedora and `curl | sudo bash` setup script for Ubuntu/Debian.
- **Packaging**: Updated optional dependency descriptions across all formats (PKGBUILD, deb control, rpm spec, nix) to reflect ydotool requirement for all Wayland compositors.

## 2026-03-31 (v1.1.9669)

### Changed
- **Version bump to v1.1.9669** — New upstream release with structural changes to feature flag system.
- **New `computerUse` feature flag** added to static registry (`jun()`, darwin-only). Added override to `enable_local_agent_mode.py` merger patch (8 features now overridden, up from 7).
- **`chillingSlothFeat` darwin gate re-introduced** — Was removed upstream in v1.1.9134, now back. Our Patch 1 regex already handles it.

### Fixed
- **enable_local_agent_mode.py**: Fixed `yukonSilver` regex — function name `$un()` contains `$` which `\w+` doesn't match. Updated pattern to use `[\w$]+` for function names.

### Docs
- **CLAUDE_FEATURE_FLAGS.md**: Updated for v1.1.9669 — 18 features (was 17), new function names, new GrowthBook flags (`3691521536` stealth updater, `3190506572` Chrome perms), remote orchestrator flag `4201169164` removed.
- **CLAUDE_BUILT_IN_MCP.md**: Updated for v1.1.9669 — registration function renamed `Pee()`→`Are()`.

### New Upstream (not patched — not needed)
- **Stealth updater** (flag `3691521536`) — nudges updates when no sessions active. Works on Linux as-is.
- **Epitaxy route** (flag `1585356617`) — new CCD session URL routing with `spawn_task` tool. Not platform-gated.
- **Org plugins path** — returns `null` on Linux (graceful no-op). Only needed for enterprise deployments.
- **Remote orchestrator (manta)** — hardcoded off (`Qhn=!1`). Flag `4201169164` removed from GrowthBook.

## 2026-03-29 (v1.1.9493)

### Changed
- **Version bump to v1.1.9493** — Upstream metadata-only re-release; JS bundles are byte-for-byte identical to v1.1.9310. No new features, MCP servers, or platform checks.
- **Custom themes: visual polish** — Borders now use accent color with subtle alpha (e.g. `#cba6f718`) instead of neutral gray, matching each theme's palette. Added accent-colored scrollbars, dialog/menu/tooltip glow shadows, button hover glow, smooth transitions on interactive elements, and transparent input borders/focus rings for a cleaner look. All 6 theme JSON files updated.

### Fixed
- **fix_process_argv_renderer.py**: Platform spoof pattern (`platform="win32"`) no longer exists in mainView.js. Added primary pattern matching `exposeInMainWorld("process",<var>)` to insert `argv=[]` before the expose call. Old spoof-based and appVersion-based patterns retained as fallbacks.
- **enable_local_agent_mode.py**: Async feature merger restructured from arrow function `async()=>({...Oh(),...})` to block body with `Promise.all` and explicit `return{...vw(),...}`. Added new regex for the block-body format; old arrow-function pattern retained as fallback.

### Docs
- **CLAUDE_BUILT_IN_MCP.md**: Expanded Claude Preview section with full tool catalog (13 tools), `.claude/launch.json` configuration, and architecture description. Updated to v1.1.9493.
- **CLAUDE.md**: Added CI-managed files section documenting that README install command versions are updated automatically by CI.

## 2026-03-29 (v1.1.9310-5)

### Fixed
- **Nix hash mismatch** (#19) — CI computed the Nix SRI hash from the locally-built tarball artifact, but users download from GitHub Releases. Non-deterministic tar builds across CI re-runs caused the hash to drift from the actual release asset. Fixed by computing the hash from the downloaded release tarball instead of the build artifact. Reverted `package.nix` hash to match the actual released tarball.

## 2026-03-28 (v1.1.9310-4)

### Fixed
- **Dispatch: SendUserMessage now works natively** — CLI v2.1.86 fixed the `CLAUDE_CODE_BRIEF=1` env var parser. The Ditto dispatch orchestrator agent now calls `SendUserMessage` directly — no synthetic transform needed. Removed Patch I (bridge-level text→SendUserMessage workaround)

### Changed
- **Dispatch: removed Patch I** — The synthetic `SendUserMessage` transform in `fix_dispatch_linux.py` is no longer needed. Patch F (rjt bridge filter widening) retained as defense-in-depth for edge cases
- **Dispatch: documented Ditto architecture** — Added [Dispatch Architecture](#dispatch-architecture) section to README documenting the orchestrator agent, session types (`chat`/`agent`/`dispatch_child`), and Linux adaptations
- **SEND_USER_MESSAGE_STATUS.md** — Complete rewrite reflecting fixed state: Ditto architecture, `--disallowedTools` discovery, `present_files` interception, `SendUserMessage` full signature, version bisect updated through v2.1.86

## 2026-03-28 (v1.1.9310-3)

### Fixed
- **Launcher shebang**: Removed two leading spaces before `#!/usr/bin/env bash` that caused `Exec format error` when launched from desktop entries or protocol handlers (kernel requires `#!` at byte 0). Terminal launches were unaffected. (#17)

### Changed
- **Build: shebang validation**: `build-patched-tarball.sh` now validates that the launcher script has `#!` at byte 0 before creating the tarball, preventing this class of bug from reaching users

## 2026-03-27 (v1.1.9310)

### Changed
- **Launcher: native Wayland by default** — Wayland sessions now use native Wayland instead of XWayland. Global hotkeys (Ctrl+Alt+Space) work via `xdg-desktop-portal` GlobalShortcuts API (KDE, Hyprland; Sway/GNOME pending upstream portal support). Set `CLAUDE_USE_XWAYLAND=1` to force XWayland if needed. Niri sessions still auto-forced to native Wayland. The old `CLAUDE_USE_WAYLAND=1` env var is now a no-op (native is the default).
- **CI**: Remove push trigger from release workflow — now runs only on nightly schedule (2 AM UTC) or manual dispatch

### Fixed
- **fix_utility_process_kill.py**: Logger variable changed from `\w+` name to `$` — updated pattern to `[\w$]+` for the `.info()` call
- **fix_detected_projects_linux.py**: Same `$` logger issue — updated pattern to `[\w$]+` for the `.debug()` call
- **fix_dispatch_linux.py**: Same `$` logger issue in sessions-bridge gate pattern and auto-wake parent pattern — updated all logger references to `[\w$]+`. Dispatch now applies 8/8 sub-patches (was 6/8)

### New Upstream
- **Operon (full-stack web agent)**: Still gated behind flag `1306813456`, returns `{status:"unavailable"}` unconditionally. Will need Cowork-style patch when activated
- **Epitaxy (new sidebar mode)**: No platform gate — works on Linux as-is
- **Imagine (visual creation MCP server)**: No platform gate — works on Linux as-is

## 2026-03-27 (v1.1.9134)

### Fixed
- **enable_local_agent_mode.py — Patch 7 (mainView.js platform spoof)**: Variable `$s` contains `$` which isn't matched by `\w+`. Changed regex to use `[\w$]+` for filter variable names in `Object.fromEntries(Object.entries(process).filter(([e])=>$s[e]))`.
- **fix_computer_use_linux.py — Sub-patch 6 rewrite (hybrid handler)**: Replaced full `handleToolCall` replacement with a hybrid early-return injection. Teach tools (`request_teach_access`, `teach_step`, `teach_batch`) now fall through to the upstream chain (which uses `__linuxExecutor` via sub-patches 3-5), enabling the teach overlay on Linux. Normal CU tools keep the fast direct handler. Also fixed: variable name collisions (`var c` hoisting vs upstream `const c`).
- **fix_computer_use_linux.py — Sub-patch 8 rewrite (tooltip-bounds polling)**: Previous fix polled cursor against `getContentBounds()` (= full screen) so `setIgnoreMouseEvents(false)` was permanently set, blocking the entire desktop. Now queries the `.tooltip` card's actual `getBoundingClientRect()` from the renderer via `executeJavaScript`, checks cursor against card bounds with 15px padding. Also fixed stale cursor: Electron's `getCursorScreenPoint()` returns frozen coordinates on X11 when cursor isn't over an Electron window — now uses `xdotool getmouselocation` → `hyprctl cursorpos` → Electron API fallback chain (cached 100ms).
- **fix_computer_use_linux.py — Sub-patches 9a/9b (step transition)**: Neutralized `setIgnoreMouseEvents(true,{forward:true})` calls in `yJt()` (show step) and `SUn()` (working state) on Linux. These fought with the polling loop during step transitions. Polling now has sole control of mouse event state on Linux, with 400ms grace period.
- **fix_computer_use_linux.py — `listInstalledApps()` app resolution**: Teach mode failed with `"reason":"not_installed"` because `.desktop` display names (e.g., "Thunar File Manager") didn't match model requests (e.g., "Thunar"). Now emits multiple name variants per app: full name, short name (first word), exec name, Icon= bundleId (reverse-domain), .desktop filename. Also scans Flatpak app directories.
- **fix_computer_use_linux.py — `switch_display`**: Real implementation using `xrandr` display enumeration and `globalThis.__cuPinnedDisplay` state tracking. Screenshots respect pinned display. Replaces the previous "not available" stub.
- **fix_computer_use_linux.py — `computer_batch`**: Fixed return format to match upstream's `{completed:[...], failed:{index,action,error}, remaining:[...]}` structure instead of only returning the last result.

### Removed
- **fix_tray_path.py** — Deleted: redundant since `fix_locale_paths.py` already replaces ALL `process.resourcesPath` references globally (including the tray path function). Patch count: 33→32.

### New Upstream
- **New MCP server: `ccd_session`** — Provides `spawn_task` tool to spin off parallel tasks into separate Claude Code Desktop sessions. Gated by CCD session + server flag `1585356617`. Already Linux compatible (no platform gates).
- **5 new Computer Use tools** — `switch_display` (multi-monitor), `computer_batch` (batch actions), `request_teach_access`, `teach_step`, `teach_batch` (guided teach mode). Total tools: 22→27. All 5 now Linux compatible.
- **New feature flag: `wakeScheduler`** — macOS-only Login Items scheduling (gated by `Kge()` + darwin). Not needed on Linux — the scheduled tasks engine is platform-independent (`setInterval` + cron evaluation). Tasks fire on wake-up if missed during sleep.
- **Operon expanded**: 18→28 sub-interfaces (9 new: `OperonAgentConfig`, `OperonAnalytics`, `OperonAssembly`, `OperonHostAccessProvider`, `OperonImageProvider`, `OperonQuitHandler`, `OperonServices`, `OperonSessionManager`, `OperonSkillsSync`). Still gated behind flag `1306813456`.
- **New GrowthBook flags**: `66187241` + `3792010343` (tool use summaries), `1585356617` (epitaxy/session routing), `2199295617` (auto-archive PRs), `927037640` (subagent model config), `2893011886` (wake scheduler timing). All cross-platform, no patching needed. Removed: `3196624152` (Phoenix Rising updater).

### Added
- **Unified launcher across all packaging formats** — RPM, DEB, and AppImage now use the full launcher script (Wayland/X11 detection, SingletonLock cleanup, cowork socket cleanup, logging) instead of minimal 2-3 line stubs. Launcher auto-discovers Electron binary and app.asar paths at runtime. Fixes [#13](https://github.com/patrickjaja/claude-desktop-bin/issues/13).
- **GPU compositing fallback (`CLAUDE_DISABLE_GPU`)** — New env var to fix white screen on systems with GBM buffer creation failures (common on Fedora KDE / Wayland). `CLAUDE_DISABLE_GPU=1` disables GPU compositing; `CLAUDE_DISABLE_GPU=full` disables GPU entirely.
- **AppImage auto-update support** — AppImages now embed `gh-releases-zsync` update information and ship with `.zsync` delta files. Users can update via `appimageupdatetool`, `--appimage-update` CLI flag, or compatible tools (AppImageLauncher, Gear Lever). Only changed blocks are downloaded.
- **Wayland support in Computer Use executor** — Full auto-detection via `$XDG_SESSION_TYPE`. On Wayland: `ydotool` for input, `grim` for screenshots (wlroots), `wl-clipboard` for clipboard, Electron APIs for display enumeration and cursor position. On X11: existing tools (`xdotool`, `scrot`, `xclip`, `xrandr`). Falls back to X11/XWayland if Wayland tools are not installed. Compositor-specific window info via `hyprctl` (Hyprland) and `swaymsg` (Sway).
- **Fedora/RHEL DNF repository** — RPM packages now published to GitHub Pages alongside APT. One-line setup: `curl -fsSL .../install-rpm.sh | sudo bash`. Auto-updates via `dnf upgrade`. Scripts: `packaging/rpm/update-rpm-repo.sh`, `packaging/rpm/install-rpm.sh`.

### Changed
- **Dependencies** — Moved `nodejs` from `depends` to optional across all formats (Electron bundles Node.js; system node only needed for MCP extensions requiring specific versions). Added Wayland optdeps (`ydotool`, `grim`, `slurp`, `wl-clipboard`, `wlr-randr`) and `xorg-xrandr` with (X11)/(Wayland) annotations. Updated: PKGBUILD.template, debian/control, rpm/spec, nix/package.nix.
- **CLAUDE_BUILT_IN_MCP.md** — Updated for v1.1.9134: new `ccd_session` server, 5 new computer-use tools, registration function rename `IM()`→`Pee()`, expanded Operon sub-interfaces.
- **CLAUDE_FEATURE_FLAGS.md** — Updated for v1.1.9134: new `wakeScheduler` (17 features total), function renames (`dA`→`rw`, `JX`→`yre`, `Oet`→`Kge`, `Hn`→`kn`, `Hk`→`bC`), 4 new GrowthBook flags, 1 removed flag.
- **README.md** — Fedora section updated from manual download to DNF repo with auto-updates. Computer Use feature description updated with Wayland/X11 tool split.

### CI
- **Parallelized GitHub Actions workflow** — Refactored monolithic single-job pipeline into fan-out/fan-in pattern with 8 jobs. Package builds (AppImage, DEB, RPM × 2 architectures), Nix test, and PKGBUILD generation now run in parallel on separate runners after the tarball build. Estimated ~6 min savings per run.

### Notes
- **All 32 patches pass** with zero failures on v1.1.9134.
- **Computer Use teach mode** now works on Linux — the teach overlay is pure Electron `BrowserWindow` + IPC, not macOS-specific. The hybrid handler routes teach tools through the upstream chain while keeping the fast direct handler for normal tools.
- **No new platform gates** blocking core Linux functionality. The 4 new GrowthBook flags and `ccd_session` MCP server are all platform-independent.
- **Verified all existing patches still needed** — upstream has NOT removed darwin gates for chillingSlothFeat, yukonSilver, or navigator spoofs despite initial false positive (caused by inspecting already-patched files).

## 2026-03-25 (v1.1.8629)

### Fixed
- **fix_dispatch_linux.py — Patch A (Sessions-bridge gate)**: Variable declaration changed from single (`let f=!1;const`) to triple (`let f=!1,p=!1,h=!1;const`). Updated regex to handle comma-separated declarations with `(?:\w+=!1,)*` prefix. The gate variable `h` is now `h = f || p` where `p` is the new remote orchestrator flag.
- **fix_dispatch_linux.py — Patch J (Auto-wake parent)**: Logger variable renamed `B` → `P`. Converted from hardcoded byte string to regex with dynamic capture group for the logger variable.
- **fix_dispatch_linux.py — Patch K (present_files unblock)**: Removed `mcp__cowork__present_files` from `RIt` renderer-dependent disallowed tools list. This tool works through the MCP proxy and doesn't need the local renderer. Without this, dispatch file sharing (e.g. PDF generation from phone) gets "Permission denied".

### New Upstream
- **Feature flag `4201169164`** — Remote Orchestrator (codename "manta" / `yukon_silver_manta_desktop`). Alternative to local Cowork: connects to Anthropic's cloud via WebSocket (`wss://bridge.claudeusercontent.com`) instead of local `cowork-svc`. Enabled via env var `CLAUDE_COWORK_FORCE_REMOTE_ORCHESTRATOR=1` or developer setting `isMantaDesktopEnabled`. Not tested on Linux — likely requires Pro account or server-side enablement.
- **16 i18n locale files** — de-DE, en-US, en-XA, en-XB, es-419, es-ES, fr-FR, hi-IN, id-ID, it-IT, ja-JP, ko-KR, pt-BR, xx-AC, xx-HA, xx-LS. Already handled by build script's i18n copy step.
- **Developer setting `isMantaDesktopEnabled`** — New toggle in developer settings: "Forces yukon_silver_manta_desktop (remote orchestrator mode) regardless of GrowthBook".

### Changed
- **CLAUDE_FEATURE_FLAGS.md** — Updated for v1.1.8629: new flag `4201169164` (remote orchestrator), function renames (`Qn`→`Hn`, `Bx`→`Hk`, `lA`→`dA`, `jY`→`JX`, `VKe`→`Oet`), documented remote orchestrator architecture and env vars.

### Notes
- **No new platform gates** — No new `darwin`/`win32`-only patterns found. All 32 existing patches still required.
- **All 32 patches pass** with zero failures on v1.1.8629. Only variable name renames (handled by `\w+` wildcards).

## 2026-03-24 (v1.1.8359)

### Added
- **fix_computer_use_linux.py** — New patch: enables Computer Use on Linux with 6 sub-patches. Removes 3 upstream platform gates (`b7r()`, `ZM()`, `createDarwinExecutor`), provides a Linux executor using xdotool/scrot/xclip/wmctrl, bypasses macOS TCC permissions (`ensureOsPermissions` returns granted), and replaces the macOS permission model (`rvr()` allowlist/tier system) with direct tool dispatch. 22 tools work immediately without `request_access` — no app tier restrictions, no bundle ID matching, no permission dialogs.
- **fix_detected_projects_linux.py** — New patch: enables Recent Projects on Linux. Maps VSCode (`~/.config/Code/`), Cursor (`~/.config/Cursor/`), and Zed (`~/.local/share/zed/`) workspace detection paths. Home directory scanner already works cross-platform.
- **fix_enterprise_config_linux.py** — New patch: reads enterprise config from `/etc/claude-desktop/enterprise.json` on Linux. Returns `{}` if file doesn't exist (preserving current behavior).

### Changed
- **fix_marketplace_linux.py** — Simplified: removed dead Pattern A (runner selector, refactored upstream) and Pattern B (search_plugins, removed upstream). Only Pattern C (CCD gate) remains.
- **CLAUDE_FEATURE_FLAGS.md** — Updated for v1.1.8359: new `operon` feature (#16), function renames, 4 new GrowthBook flags, 2 removed flags.
- **CLAUDE_BUILT_IN_MCP.md** — Updated for v1.1.8359: Operon IPC system (120+ endpoints), visualize factory rename, all 14 MCP servers unchanged.
- **README.md** — Added new patches to table, removed `fix_mcp_reconnect.py`, added Known Limitations section (Browser Tools).

### Removed
- **fix_mcp_reconnect.py** — Deleted: close-before-connect fix is now upstream (since v1.1.4088+). Patch was a no-op.

### Notes
- **Computer Use MCP is back** — Removed in v1.1.7714 (commit 2c69b13) when upstream dropped the standalone `computer-use-server.js`. Now reintroduced as a built-in internal MCP server integrated into `index.js`. Upstream gates it to macOS-only (`@ant/claude-swift`); our patch provides a Linux-native implementation.
- **Operon (Nest)** — Major new upstream feature (120+ IPC endpoints). Currently server-gated (flag `1306813456`), requires VM infrastructure. Not patched — waiting for Anthropic to enable.
- **Browser Tools** — Documented as known limitation. Server registration requires `chrome-native-host` binary (Rust, proprietary, Windows/macOS only).

## 2026-03-23 (v1.1.8308)

### Added
- **fix_office_addin_linux.py** — New patch: enable Office Addin MCP server on Linux by extending the `(ui||as)` platform gate in 3 locations (MCP isEnabled, init block, connected file detection). The underlying WebSocket bridge is platform-agnostic; this enables future compatibility with web Office or LibreOffice add-ins.
- **fix_read_terminal_linux.py** — New patch: enable `read_terminal` built-in MCP server on Linux (was hardcoded to `darwin` only). Reads integrated terminal panel content in CCD sessions.
- **fix_browse_files_linux.py** — New patch: add `openDirectory` to the browseFiles file dialog on Linux. Electron fully supports directory selection on Linux but upstream only enabled it for macOS.

### Fixed
- **fix_process_argv_renderer.py** — Fix for v1.1.8308: hardcoded `Ie` variable name → dynamic `\w+` capture. Upstream renamed the process proxy from `Ie` to `at`.
- **fix_quick_entry_position.py** — Fix for v1.1.8308: hardcoded `ai` window variable → dynamic `[\w$]+` capture group. Upstream renamed Quick Entry window var from `ai` to `Js`.
- **fix_dispatch_linux.py** — Enhanced Patch I: now also transforms `mcp__cowork__present_files` tool_use blocks into SendUserMessage attachments, so file sharing renders on the phone.

### Previous (2026-03-23)

### Fixed
- **fix_dispatch_linux.py — Restore Patch I (text→SendUserMessage transform)** — Claude Code CLI 2.1.x has a bug where `--brief` + `--tools SendUserMessage` does not expose the `SendUserMessage` tool to the model. The model falls back to plain text, which the sessions API silently drops (only `SendUserMessage` tool_use blocks are rendered on the phone). Patch I injects a transform in `forwardEvent()` that wraps plain text assistant messages as synthetic `SendUserMessage` tool_use blocks before writing to the transport.

### Changed
- ~~fix_dispatch_linux.py — Removed Patch I~~ — Reverted: Patch I is needed as a workaround for the CLI `SendUserMessage` bug

### Added
- **CLAUDE_BUILT_IN_MCP.md — Per-session dynamic MCP servers** — Documented 4 SDK-type MCP servers created dynamically per cowork/dispatch session: `dispatch` (6 tools), `cowork` (4 tools), `session_info` (2 tools), `workspace` (2 tools). Includes tool schemas, registration method, allowedTools/disallowedTools logic, and SDK server architecture diagram comparing Mac/Windows VM vs Linux native paths.
- **fix_updater_state_linux.py** — New patch: add `version`/`versionNumber` empty strings to idle updater state so downstream code calling `.includes()` on `version` doesn't crash with `TypeError: Cannot read properties of undefined`
- **fix_process_argv_renderer.py** — New patch: inject `Ie.argv=[]` into preload so SDK web bundle's `process.argv.includes("--debug")` no longer throws TypeError

### Fixed
- **Dispatch text responses now render** — Patched the sessions-bridge `rjt()` filter (Patch F) to forward text content blocks and SDK MCP tool_use responses (`mcp__dispatch__send_message`, `mcp__cowork__present_files`)
- **Navigator platform timing gap** — Changed navigator.platform spoofing from `dom-ready` only to both `did-navigate` + `dom-ready` fallback, closing the window where page scripts see real `navigator.platform` while `process.platform` is already spoofed to `"win32"`
- **Removed diagnostic patches G/H** — forwardEvent and writeEvent logging removed from fix_dispatch_linux.py (no longer needed)

### Documentation
- **CLAUDE.md** — Added "Dispatch Debug Workflow" section with step-by-step debug commands for bridge events, audit analysis, cowork-service args, and session clearing
- **README.md** — Added "Clear Dispatch session" troubleshooting section

## 2026-03-20

### Added
- **Custom Themes (Experimental)** — New `add_feature_custom_themes.py` patch: inject CSS variable overrides into **all windows** (main chat, Quick Entry, Find-in-Page, About) via Electron's `insertCSS()` API. Ships 6 built-in themes (sweet, nord, catppuccin-mocha, catppuccin-frappe, catppuccin-latte, catppuccin-macchiato). Configure via `~/.config/Claude/claude-desktop-bin.json`.
- **themes/** — Community theme directory with ready-to-use JSON configs, screenshots, CSS variable reference (`css-documentation.html`), and `README.md` documenting how to extract app HTML/CSS for theme creation
- **Full-window theming** — Quick Entry gradient, prose/typography (`--tw-prose-*`), `--always-black/white` shadows, checkbox accents, title bar text now all follow the active theme

### Changed
- **CLAUDE_FEATURE_FLAGS.md** — Comprehensive update for v1.1.7714: new `yukonSilverGemsCache` feature (15 total), complete GrowthBook flag catalog (34 boolean + 9 object/value + 3 listener flags), function renames (fp/cN/r1e/xq), version history table updated

### Added
- **fix_quick_entry_position.py** — Two new sub-patches for v1.1.7714:
  - Patch 3: Override position-save/restore (`T7t()`) to always use cursor's display (short-circuits saved position check)
  - Patch 4: Fix show/positioning + focus on Linux — pure Electron APIs, no external dependencies

### Fixed
- **fix_quick_entry_position.py (Patches 1 & 2)** — Fix stale cursor position on Linux: `Electron.screen.getCursorScreenPoint()` only updates when the cursor passes over an Electron-owned window, causing Quick Entry to always open on the app's monitor. Now uses `xdotool getmouselocation` (X11/XWayland) → `hyprctl cursorpos` (Hyprland/Wayland) → Electron API as defensive fallback chain. Both tools are optional — graceful degradation if unavailable.
- **Packaging** — Added `xdotool` as optional dependency across all formats (AUR `optdepends`, Debian `Suggests`, RPM `Suggests`, Nix optional input with PATH wiring)
- **fix_quick_entry_position.py (Patch 4)** — Complete rewrite of Linux Quick Entry positioning and focus:
  - **Positioning**: `setBounds()` before + after `show()` with retries at 50/150ms to counter X11 WM smart-placement. Works on X11, XWayland, and best-effort on native Wayland.
  - **Focus**: Three-layer focus chain — `focus()` (OS window) → `webContents.focus()` (renderer) → `executeJavaScript` to focus `#prompt-input` DOM element (only auto-focuses on initial page load, not on hide/show cycle).
  - Previously the Quick Entry would always open on Claude Desktop's monitor after interacting with the app, making it unusable in multi-monitor setups.
- **CLAUDE_BUILT_IN_MCP.md** — New documentation: built-in MCP server reference
- **docs/** — Screenshots directory

### Fixed
- **fix_dispatch_linux.py** — Fix sessions-bridge logger variable pattern: hardcoded `T` → `\w+` wildcard (logger renamed `T`→`C` in v1.1.7714)
- **fix_cowork_spaces.py** — Fix `createSpaceFolder` API: takes `(parentPath, folderName)` not `(spaceId, folderName)`; adds duplicate folder name dedup with numeric suffix
- **enable_local_agent_mode.py** — Promote platform spoof patches from WARN to FAIL (patches 5, 5b, 6, 7 are now required — if they don't match, the build should fail)
- **fix_utility_process_kill.py** — Promote from WARN/pass to FAIL (exit 1 on 0 matches so CI catches pattern changes)

### Removed
- **computer-use-server.js** — Linux Computer Use MCP server removed (upstream removed `computer-use-server.js` from app root in v1.1.7714; `existsSync` guard fails at runtime, server never registers)
- **fix_computer_use_linux.py** — Computer Use registration patch removed (no server file to register)
- **PKGBUILD** — Removed `scrot` optional dependency (Computer Use removed); added `hyprland` (hyprctl cursor fallback) and `socat` (cowork socket health check)

### Improved
- **scripts/build-local.sh** — Auto-download latest exe with version comparison: queries version API first, skips download if local exe matches latest, saves downloaded exe for future builds

## 2026-03-19

### Changed
- **Update to Claude Desktop v1.1.7464** (from v1.1.7053)

### Added
- **fix_dispatch_linux.py** — New patch: enables Dispatch (remote task orchestration from mobile) on Linux. Four sub-patches:
  - A: Forces sessions-bridge init gate ON (GrowthBook flag `3572572142` — `let f=!1` → `let f=!0`)
  - B: Bypasses remote session control check (GrowthBook flag `2216414644` — `!Jr(...)` → `!1`)
  - C: Adds Linux to `HI()` platform label (`"Unsupported Platform"` → `"Linux"`)
  - D: Includes Linux in `Xqe` telemetry gate so dispatch analytics are not silently dropped
- **fix_window_bounds.py** — New patch: fixes three window management issues on Linux:
  - Child view bounds fix: hooks maximize/unmaximize/fullscreen/moved events to manually set child view bounds (fixes blank white area on KWin corner-snap)
  - Ready-to-show size jiggle: +1px resize then restore after 50ms to force Chromium layout recalculation on first load
  - Quick Entry blur before hide: adds `blur()` before `hide()` for proper focus transfer
- **scripts/claude-desktop-launcher.sh** — New launcher script replacing the bare `exec electron` one-liner:
  - Wayland/X11 detection (defaults to XWayland for global hotkey support, `CLAUDE_USE_WAYLAND=1` for native Wayland)
  - Auto-detects Niri compositor (forces native Wayland — no XWayland)
  - Electron args: `--disable-features=CustomTitlebar`, `--ozone-platform`, `--enable-wayland-ime`, etc.
  - Environment: `ELECTRON_FORCE_IS_PACKAGED=true`, `ELECTRON_USE_SYSTEM_TITLE_BAR=1`
  - SingletonLock cleanup (removes stale lock files from crashed sessions)
  - Cowork socket cleanup (removes stale `cowork-vm-service.sock`)
  - `CLAUDE_MENU_BAR` support (auto/visible/hidden)

### Fixed
- **Navigator spoof changed from Mac to Windows** — `navigator.platform` now returns `"Win32"` instead of `"MacIntel"` and `userAgentFallback` spoofs as Windows, so the frontend shows Ctrl/Alt shortcuts instead of ⌘/⌥. Server-facing HTTP headers still send "darwin" for Cowork feature gating.

### Notes
- 27/27 patches pass (fix_mcp_reconnect.py: upstream fix, no patch needed)
- Feature flag architecture unchanged from v1.1.7053 — same 14 flags, same 3-layer override
- New upstream features in v1.1.7464: SSH remote CCD sessions, Scheduled Tasks (cron), Teleport to Cloud, Git/PR integration, DXT extensions, Keep-Awake
- New sidebar mode: `"epitaxy"` (purpose unknown)
- CoworkSpaces fully implemented on Linux — file-based `_SpacesService` with JSON persistence, 17 CRUD/file methods, push events, and SpaceManager singleton integration. Spaces UI is rendered by the claude.ai web frontend (server-side gated by Anthropic, not desktop feature flags). Dispatch works independently of Spaces (spaceId is optional in session creation)
- Function renames: rp/zM/$Se/oq (was Kh/$M/Qwe/K9)
- eipc UUID: `fcf195bd-4d6c-4446-98e4-314753dfa766` (dynamically extracted)

## 2026-03-17

### Changed
- **Update to Claude Desktop v1.1.7053** (from v1.1.3189)

### Added
- **fix_cowork_spaces.py** — New patch: injects a full file-based CoworkSpaces service on Linux. The renderer calls `getAllSpaces`, `createSpace`, `getAutoMemoryDir`, etc. via eipc but no handler is registered in the main process on Linux (native backend doesn't load). The `_SpacesService` class provides JSON persistence (`~/.config/Claude/spaces.json`), full CRUD for spaces/folders/projects/links, file operations with security validation, push event notifications, and SpaceManager singleton integration so `resolveSpaceContext` works.

### Fixed
- **enable_local_agent_mode.py** — Fix mC() merger pattern: `\w+` → `[\w$]+` for the async merger variable name (was `$M` in this version, `$` not matched by `\w`)

### Notes
- 24/24 patches pass (fix_mcp_reconnect.py: upstream fix, no patch needed)
- New feature flag `floatingAtoll` added upstream (always `{status:"unavailable"}` — disabled for all platforms, no Linux patch needed)
- New settings: `chicagoEnabled`, `keepAwakeEnabled`, `coworkScheduledTasksEnabled`, `ccdScheduledTasksEnabled`, `sidebarMode`, `bypassPermissionsModeEnabled`, `autoPermissionsModeEnabled`
- New developer flags: `isPhoenixRisingAgainEnabled` (new updater), `isDxtEnabled`/`isDxtDirectoryEnabled` (browser extensions), `isMidnightOwlEnabled`
- eipc UUID changed to `316b9ec7-48bb-494d-b1a8-82f8448548fb` (dynamically extracted by fix_computer_use_tcc.py)
- Function renames: Kh/$M/Qwe/K9 (was nh/rO/Ebe/J5)
- `fix_marketplace_linux.py` Patches A & B return 0 matches (patterns refactored upstream); Patch C (CCD gate) still active

## 2026-03-15

### Fixed
- **fix_dock_bounce.py** — Comprehensive fix for taskbar attention-stealing on KDE Plasma and other Linux DEs ([#10](https://github.com/patrickjaja/claude-desktop-bin/issues/10)). Previous approach only patched `BrowserWindow.prototype` methods but missed `WebContents.focus()` which bypasses those overrides entirely and triggers `gtk_window_present()`/`XSetInputFocus()` at the C++ level, causing `_NET_WM_STATE_DEMANDS_ATTENTION`. New approach:
  - **Layer 1 (prevent):** No-op `flashFrame(true)`/`app.focus()`, guard `BrowserWindow.focus()`/`moveTop()`, use `showInactive()` instead of `show()` when app not focused, enable `backgroundThrottling` on Linux, early-return `requestUserAttention()`, **intercept `WebContents.focus()` via `web-contents-created` event** (the key fix — only allow when parent window is focused)
  - **Layer 2 (cure):** On every window blur, actively call the real `flashFrame(false)` on a 500ms interval to continuously clear demands-attention state set by Chromium internals. Stops on focus.

## 2026-03-11

### Changed
- **Update to Claude Desktop v1.1.6041** (from v1.1.5749)

### Fixed
- **fix_computer_use_tcc.py** — Dynamically extract eipc UUID from source files instead of hardcoding it. The UUID changed from `a876702f-...` to `dbb8b28b-...` between versions, causing `No handler registered for ComputerUseTcc.getState` errors. Now searches index.js (fallback: mainView.js) for the UUID at patch time, making the patch resilient to future UUID rotations.

### Notes
- 22/22 patches pass (fix_mcp_reconnect.py: upstream fix, no patch needed)
- No new platform gates requiring patches — all critical darwin/win32 checks already handled
- Upstream now ships Linux CCD binaries (linux-x64, linux-arm64, musl variants) and Linux VM rootfs images in manifest
- New IPC handler groups: CoworkScheduledTasks, CoworkSpaces, CoworkMemory, LocalSessions SSH/Teleport, expanded Extensions
- New `sshcrypto.node` native addon for SSH support (not yet needed for core functionality)
- `louderPenguin` (Office Addin) remains darwin+win32 only — no action needed for Linux

## 2026-03-09

### Changed
- **Update to Claude Desktop v1.1.5749** (from v1.1.4498)

### Fixed
- **fix_disable_autoupdate.py** — Handle new `forceInstalled` check before platform gate in isInstalled function (pattern: `if(Qm.forceInstalled)return!0;if(process.platform!=="win32")...`)
- **claude-native.js** — Add stubs for new native methods: `readRegistryValues`, `writeRegistryValue`, `readRegistryDword`, `getCurrentPackageFamilyName`, `getHcsStatus`, `enableWindowsOptionalFeature`, `getWindowAbove`, `closeOfficeDocument`, `isProcessRunning`, `readCfPrefValue`
- **fix_marketplace_linux.py** — Downgrade runner selector and search_plugins handler patterns from FAIL to INFO (patterns removed in v1.1.5749 marketplace refactor; CCD gate patch C remains the essential fix)

### Added
- **fix_computer_use_tcc.py** — Register stub IPC handlers for ComputerUseTcc on Linux. The renderer (mainView.js) always calls `ComputerUseTcc.getState` but handlers are only registered by `@ant/claude-swift` on macOS. Stubs return `not_applicable` for permissions, preventing repeated IPC errors.
- **computer-use-server.js** — Linux Computer Use MCP server using xdotool (input) and scrot (screenshots) on X11. Provides 14 actions: left_click, right_click, double_click, triple_click, middle_click, type, key, screenshot, scroll, left_click_drag, hover, wait, zoom, cursor_position.
- **fix_computer_use_linux.py** — Registers computer-use-server.js as an internal MCP server via BR() (registerInternalMcpServer), spawning it as a Node.js child process with ELECTRON_RUN_AS_NODE=1. Only activates on Linux.
- **Packaging** — Added `xdotool` and `scrot` as optional dependencies across all formats: `optdepends` (Arch PKGBUILD), `Suggests` (Debian control, RPM spec), optional inputs with PATH wiring (Nix package.nix)

### Notes
- 22/22 patches pass (fix_mcp_reconnect.py: upstream fix, no patch needed)
- Computer Use requires `xdotool` and `scrot` packages (X11). Wayland not yet supported. Both are declared as optional dependencies across all packaging formats (AUR, Debian, RPM, Nix).
- No new feature flags detected (same 7: quietPenguin, louderPenguin, chillingSlothFeat, chillingSlothLocal, yukonSilver, yukonSilverGems, ccdPlugins)
- getLocalFileThumbnail uses pure Electron nativeImage API — no native stub needed
- Bridge methods (respondPluginSearch, kickBridgePoll, BridgePermission) are Electron IPC only

## 2026-03-02

### Fixed
- **scripts/build-patched-tarball.sh** — Bundle `claude-ssh` binaries from Windows package into `locales/claude-ssh/` to fix SSH remote environment feature ([#8](https://github.com/patrickjaja/claude-desktop-bin/issues/8))
- **patches/fix_0_node_host.py** — Fix shell path worker error (`Shell path worker not found at .../locales/app.asar/...`) by replacing `process.resourcesPath,"app.asar"` with `app.getAppPath()` before the global locale path redirect
- **PKGBUILD.template** — Restore `{{placeholders}}` so `generate-pkgbuild.sh` can substitute version/URL/SHA; hardcoded values caused local builds to use stale cached tarballs missing `claude-ssh` binaries
- **patches/claude-native.js** — Fix patch target from `app.asar.contents/node_modules/claude-native/` to `app.asar.unpacked/node_modules/@ant/claude-native/` to eliminate `ERR_DLOPEN_FAILED` invalid ELF header error
- **scripts/build-patched-tarball.sh** — Remove Windows `claude-native-binding.node` DLL after asar repack to prevent shipping unusable PE32 binary
- **packaging/debian/build-deb.sh** — Set SUID permission (4755) on `chrome-sandbox` after Electron extraction and in `postinst` script to fix startup crash on Ubuntu/Debian
- **packaging/rpm/claude-desktop-bin.spec** — Set SUID permission on `chrome-sandbox` in `%post` and `%files` sections to fix startup crash on RPM-based distros

## 2026-02-27

### Changed
- **PKGBUILD.template** — Set `url` to GitHub packaging repo instead of claude.ai per AUR guidelines

## 2026-02-25

### Changed
- **Update to Claude Desktop v1.1.4328** (from v1.1.4173)

### Fixed
- **enable_local_agent_mode.py** — Make yukonSilver formatMessage `id` field optional in regex (`(?:,id:"[^"]*")?`) to handle v1.1.4328 adding i18n IDs
- **enable_local_agent_mode.py** — Use `[\w$]+` instead of `\w+` for getSystemInfo `total_memory` variable (`$r` contains `$`)

### Notes
- 4 new IPC handlers: `CoworkSpaces.copyFilesToSpaceFolder`, `CoworkSpaces.createSpaceFolder`, `FileSystem.browseFiles`, `LocalSessions.delete`
- All 19 patches pass, no structural changes to platform gating or feature flags
- Key renames: chillingSlothFeat=TMt, quietPenguin=MMt, yukonSilver=RMt, os module=`$r`

## 2026-02-24

### Changed
- **Update to Claude Desktop v1.1.4088** (from v1.1.3918)

### Fixed
- **fix_disable_autoupdate.py** — Use `[\w$]+` instead of `\w+` for Electron module variable (`$e` contains `$`)
- **fix_marketplace_linux.py** — Use `[\w$]+` for all variable patterns; gate function renamed `Hb`→`$S`, managers `gz`→`CK`/`$K`
- **fix_quick_entry_position.py** — Use `[\w$]+` for Electron module variable; make fallback display patch optional (lazy-init pattern removed upstream)
- **fix_tray_icon_theme.py** — Use `[\w$]+` for Electron module variable (`$e`)
- **fix_mcp_reconnect.py** — Detect upstream close-before-connect fix and skip gracefully (upstream added `t.transport&&await t.close()`)
- **enable_local_agent_mode.py** — Add second regex variant for the yukonSilver (NH/WOt) platform gate to support v1.1.4173+ `formatMessage` pattern alongside the old template literal pattern

### Added
- **update-prompt.md** — New "Step 0: Clean Slate" section for removing stale artifacts before version updates
- **CLAUDE.md** — Added log files section documenting runtime logs at `~/.config/Claude/logs/`

### Notes
- Key renames: Electron module `Pe`→`$e`, CCD gate `Hb`→`$S`, marketplace managers `gz`/`mz`→`CK`/`$K`
- MCP reconnect fix is now upstream — patch detects and skips
- Common fix: `$` in minified JS identifiers requires `[\w$]+` in regex patterns

## 2026-02-21

### Changed
- **Update to Claude Desktop v1.1.3918** (from v1.1.3770)

### Added
- **RPM packaging** — `packaging/rpm/build-rpm.sh` + `claude-desktop-bin.spec` for Fedora/RHEL; builds in `fedora:40` container during CI, `.rpm` included in GitHub Release assets
- **NixOS packaging** — `flake.nix` + `packaging/nix/package.nix` using system Electron via `makeWrapper`; `packaging/nix/update-hash.sh` helper for version bumps
- **CI: RPM build/test** — Fedora container builds and smoke-tests the `.rpm` before release
- **CI: Nix build** — Validates `nix build` succeeds during CI; uses local `file://` tarball to avoid hash mismatch with not-yet-created GitHub release

### Fixed
- **enable_local_agent_mode.py** — Use `[\w$]+` instead of `\w+` for async merger function names (`$Pt` contains `$`); also make User-Agent spoof pattern variable-agnostic (`\w+\.set` instead of hardcoded `s\.set`)
- **fix_cowork_linux.py** — Use regex instead of literal match for error detection pattern; variable name changed from `t` to `e` in v1.1.3918

### Added
- **fix_mcp_reconnect.py** — New patch: fix MCP server reconnection error ("Already connected to a transport") by calling `close()` before `connect()` in the `connect-to-mcp-server` IPC handler

### Documentation
- **CLAUDE_FEATURE_FLAGS.md** — Updated for v1.1.3918: function renames (Oh→Fd, mC→mP, QL→o_e), `chillingSlothEnterprise` moved to static layer, `mP` simplified to only override `louderPenguin`, `ccdPlugins` inlined, added version history table

### Notes
- Key renames: Oh()→Fd(), mC()→mP, QL()→o_e(), all individual feature functions renamed
- `chillingSlothLocal` now unconditionally returns supported (no more win32/arm64 gate)
- `louderPenguin` removed from Fd() entirely, only exists in mP async merger

## 2026-02-20

### Changed
- **Update to Claude Desktop v1.1.3770** (from v1.1.3647)

### Fixed
- **fix_quick_entry_position.py** — Use `[\w$]+` instead of `\w+` for function name in position function pattern; minified name `s$t` contains `$` which `\w` doesn't match
- **fix_locale_paths.py / fix_tray_path.py** — Replace hardcoded `/usr/lib/claude-desktop-bin/locales` with runtime expression `require("path").dirname(require("electron").app.getAppPath())+"/locales"` so locale/tray paths resolve correctly for Arch, Debian, and AppImage installs (fixes [#7](https://github.com/patrickjaja/claude-desktop-bin/issues/7))
- **fix_node_host.py → fix_0_node_host.py** — Renamed so it runs before fix_locale_paths.py; regex updated to match original `process.resourcesPath` instead of post-patch hardcoded path
- **build-deb.sh** — Bundle Electron instead of depending on system `electron`; fix dependencies from Arch package names to Ubuntu/Debian shared library deps; fix launcher to use bundled binary

## 2026-02-19

### Changed
- **Update to Claude Desktop v1.1.3647** (from v1.1.3363, +284 builds)

### Fixed
- **fix_tray_path.py** — Use `[\w$]+` instead of `\w+` for function/variable names; minified name `f$t` contains `$` which `\w` doesn't match
- **fix_app_quit.py** — Same `[\w$]+` fix for variables `f$` and `u$` in the cleanup handler
- **fix_claude_code.py** — `getHostPlatform()` pattern updated: win32 block now has arm64 conditional (`e==="arm64"?"win32-arm64":"win32-x64"`) instead of hardcoded `"win32-x64"`. Also tightened the "already patched" idempotency check to prevent false positives from other patches' `if(process.platform==="linux")` injections
- **fix_claude_code.py** / **fix_cowork_linux.py** — Claude Code binary resolution now falls back to `which claude` dynamically when not found at standard paths, supporting npm global, nvm, and other non-standard install locations. `getStatus()` also gains the `which` fallback so the Code tab submit button no longer shows "Downloading dependencies..." for non-standard installs

### Documentation
- **CLAUDE_FEATURE_FLAGS.md** — Updated for v1.1.3770: added `ccdPlugins` (#13), updated `louderPenguin` gate info (async override in mC), added org-level settings section
- **enable_local_agent_mode.py** — Added `ccdPlugins:{status:"supported"}` to mC() override (7 features total)
- **update-prompt.md** — Added Feature Flag Audit prompt (Prompt 3) for version updates

### Notes
- New upstream feature: `ccdPlugins` added to Oh() static registry, `louderPenguin` moved from QL()-wrapped to direct call with `Xi()` feature check
- New settings: `chillingSlothLocation`, `secureVmFeaturesEnabled`, `launchEnabled`, `launchPreviewPersistSession`
- Key renames: function names now use `$` in identifiers (e.g., `f$t`, `f$`, `u$`)

## 2026-02-18

### Changed
- **Update to Claude Desktop v1.1.3363** (from v1.1.3189, 174 builds ahead)

### Fixed
- **fix_claude_code.py** — `getStatus()` regex now uses `[\w$]+` instead of `\w+` for the status enum name, fixing match failure when minifier produces `$`-prefixed identifiers (e.g. `$s`)
- **fix_marketplace_linux.py** — CCD gate function name and runner selector now use flexible `\w+` patterns instead of hardcoded `Hb`/`oAt` (function renamed to `Gw` in v1.1.3363)

### Added
- **update-prompt.md** — Reusable prompts for future version updates (build & fix, diff & discover)

### Notes
- Diff analysis shows only minified variable renames between v1.1.3189 and v1.1.3363
- One new feature flag `4160352601` (VM heartbeat auto-restart) — no Linux patch needed
- Key renames: `la()` → `Xi()` (feature flags), `Hb` → `Gw` (CCD gate), `Cs` → `$s` (status enum), `tt` → `rt` (path module)

## 2026-02-17

### Changed
- **Adapt download pipeline to new CDN structure** — Old `/latest/Claude-Setup-x64.exe` URL now returns 404 and the redirect endpoint returns a 6.7MB bootstrapper instead of the full installer. Updated `build-local.sh` and CI workflow to query the `.latest` JSON API for version+hash, then download the full 146MB installer from the hash-named URL.

### Fixed
- **"Manage" plugin sidebar flashes and closes on Cowork tab** — Patch `Hb()` (the CCD/Cowork gate function) to return true on Linux, routing all plugin operations through host-local CCD paths instead of account-scoped Cowork paths. On Linux there's no VM, so the CCD path is always correct. This single change fixes 5 call sites: runner selection (`oAt`), getPlugins, uploadPlugin, deletePlugin, and setPluginEnabled. The sidebar was closing because `getPlugins` looked in account-scoped directories where `gz` (host runner) hadn't installed anything.
- **Browse Plugins empty on Cowork tab** — New `fix_marketplace_linux.py` forces the host CLI runner (`gz`) for marketplace operations on Linux. Previously, the Cowork tab selected the VM runner (`mz`) which routed `claude plugin marketplace` commands through the daemon, failing with `MARKETPLACE_ERROR:UNKNOWN`. Since marketplace management is a host filesystem operation, the host runner is always correct on Linux.

### Known Issues
- **Cowork sidebar sessions** — Previous local sessions may not appear in the sidebar due to `local_`-prefixed UUIDs failing server-side validation. This is an upstream issue in the claude.ai renderer code.

## 2026-02-16

### Fixed
- **AUR sha256sum mismatch on patch releases** — Source filename now includes `pkgrel` (`claude-desktop-VERSION-PKGREL-linux.tar.gz`) so makepkg cache is busted on patch rebuilds. CI reordered to create GitHub Release before pushing to AUR, with a download verification step to prevent referencing non-existent tarballs.

- **Browse/Web Search in Cowork sessions** — MCP server proxying now works end-to-end. Requires `claude-cowork-service >= 0.3.2` which stops blocking MCP traffic between Claude Code and Desktop.

- **fix_cowork_linux.py** — Use empty bundle file list (`linux:{x64:[]}`) instead of copying win32's list. No VM files are needed since the native Go backend runs Claude Code directly. Empty array makes download status return Ready immediately, avoiding ENOSPC (tmpfs full) and EXDEV errors.
- **fix_cross_device_rename.py** — Use flexible `\w+` pattern for fs module name (changes between versions: `zr`, `ur`, etc.) and negative lookbehind to skip rename calls already inside try blocks

## 2026-02-11

### Changed
- **Multi-distro cowork install docs** — README Cowork section now includes universal curl one-liner alongside AUR instructions

### Added
- **Cowork Linux support (experimental)** — New `fix_cowork_linux.py` patch enables the Cowork VM feature on Linux:
  - Extends TypeScript VM client (`vZe`) to load on Linux instead of requiring `@ant/claude-swift`
  - Adds Unix domain socket path (`$XDG_RUNTIME_DIR/cowork-vm-service.sock`) as Linux alternative to Windows Named Pipe
  - Adds Linux platform to bundle config for VM image downloads
  - Requires `claude-cowork-service` daemon running on the host (QEMU/KVM-based)
- **claude-cowork-service optional dependency** — PKGBUILD now lists `claude-cowork-service` as optional for Cowork VM features
- **Cowork error messages** — New `fix_cowork_error_message.py` replaces Windows-centric "VM service not running" errors with Linux-friendly guidance pointing users to `claude-cowork-service`
- **Cross-device rename fix** — New `fix_cross_device_rename.py` handles EXDEV errors when moving VM bundles from `/tmp` (tmpfs) to `~/.config/Claude/`
- **Force rebuild workflow** — New `force_rebuild` checkbox in GitHub Actions manual trigger to rebuild and release when patches/features change without an upstream version bump. Auto-increments `pkgrel`, generates git changelog grouped by date, and updates AUR + GitHub Release

### Fixed
- **Claude Code binary discovery** — `fix_claude_code.py` and `fix_cowork_linux.py` now check multiple paths (`/usr/bin/claude`, `~/.local/bin/claude`, `/usr/local/bin/claude`) instead of only `/usr/bin/claude`, fixing "Downloading dependencies..." stuck state and cowork spawn failures for npm-installed Claude Code

### Changed
- **fix_vm_session_handlers.py** — Removed Linux platform stubs (getDownloadStatus, getRunningStatus, download, startVM); these methods now call through to the real TypeScript VM client which talks to the daemon via Unix socket. Only the global uncaught exception handler remains as a safety net.

### Removed
- **fix_hide_cowork_tab.py** — Deleted; the Cowork tab is now functional on Linux when the daemon is running. Without the daemon, connection errors appear naturally in the UI.

## 2026-02-10

### Added
- **Runtime smoke testing in CI** — Three layers of defense to prevent broken builds reaching users:
  - Brace mismatch in `fix_vm_session_handlers.py` now fails the build instead of warning
  - `node --check` validates JavaScript syntax on all patched files before repacking
  - New `scripts/smoke-test.sh` runs the Electron app headlessly via `xvfb-run` for 15s to catch runtime crashes
  - CI Docker container now installs `electron` and `xorg-server-xvfb` for smoke testing

### Fixed
- **fix_vm_session_handlers.py** — Replace false-positive absolute brace count check with delta check (comparing before/after patching); add support for new `try/catch` wrapper in `getRunningStatus` pattern (v1.1.2685+)
- **enable_local_agent_mode.py** — Update mC() merger pattern for v1.1.2685: `desktopVoiceDictation` was removed from async merger, now uses flexible pattern matching the full async arrow function instead of hardcoding the last property name

## 2026-02-06

### Fixed
- **fix_hide_cowork_tab.py** — Use flexible `\w+` regex instead of hardcoded `xg` function name, preventing breakage on minified variable name changes across releases

## 2026-02-05

### Added
- **Auto-hide menu bar on Linux** — Native menu bar (File, Edit, View, Help) is now hidden by default; press Alt to show it temporarily
- **Window icon on Linux** — Claude icon now appears in the window title bar

### Fixed
- **Disable non-functional Cowork tab** — Cowork requires ClaudeVM (unavailable on Linux); tab is now visually disabled with reduced opacity and click prevention via `fix_hide_cowork_tab.py`
- **Suppress false update notifications** — New `fix_disable_autoupdate.py` patch makes the isInstalled check return false on Linux, preventing "Update heruntergeladen" popups
- **Stop force-enabling chillingSlothFeat** — `enable_local_agent_mode.py` no longer patches the chillingSlothFeat (Cowork) function or overrides it in the mC() merger; only quietPenguin/louderPenguin (Code tab) are enabled
- **Gate chillingSlothLocal on Linux** — Added Linux platform check to prevent it from returning "supported"
- **Fix startVM parameter capture** — `fix_vm_session_handlers.py` now uses dynamic parameter name capture instead of hardcoded `e`
- **Fix getBinaryPathIfReady pattern** — `fix_claude_code.py` updated for new `getLocalBinaryPath()` code path in v1.1.2102

## 2026-02-02

### Fixed
- **Top bar now clickable on Linux** - Fixed non-clickable top bar elements (sidebar toggle, back/forward arrows, Chat/Code tabs, incognito button):
  - **Root cause**: `titleBarStyle:"hidden"` creates an invisible drag region across the top ~36px on Linux, intercepting all mouse events even with `frame:true`
  - **Fix**: `fix_native_frame.py` now replaces `titleBarStyle:"hidden"` with `"default"` on Linux via platform-conditional (`process.platform==="linux"?"default":"hidden"`), targeting only the main window (Quick Entry window preserved)
  - Removed `fix_title_bar.py` and `fix_title_bar_renderer.py` (no longer needed — the native top bar works correctly once the invisible drag region is eliminated)

## 2026-01-30

### Fixed
- **Code tab and title bar for v1.1.1520** - Fixed two UI regressions after upgrading to Claude Desktop v1.1.1520:
  - **Code tab disabled**: The QL() production gate blocks `louderPenguin`/`quietPenguin` features in packaged builds. Added mC() async merger patch to override QL-blocked features, plus preferences defaults patch (`louderPenguinEnabled`/`quietPenguinEnabled` → true)
  - **Title bar missing**: Electron 39's WebContentsView architecture occludes parent webContents. Created a dedicated WebContentsView (`tb`) for the title bar that loads the same `index.html` with its own IPC handlers, positioned at y=0 with 36px height, pushing the claude.ai view down
  - Removed `fix_browserview_position.py` (title bar is now a separate WebContentsView)

### Added
- **Feature flag documentation** (`CLAUDE_FEATURE_FLAGS.md`) - Documents all 12 feature flags, the 3-layer override architecture (Oh → mC → IPC), and the QL() production gate

### Changed
- **validate-patches.sh** - Fixed exit code checking (was checking sed's exit code instead of python3's due to piping)

## 2026-01-26

### Fixed
- **Title bar and sidebar issues for v1.1.886** - Fixed two related issues where title bar hides and sidebar toggle is not clickable:
  - New patch `fix_browserview_position.py`: Fixes BrowserView y-positioning - changes `c=Ds?eS+1:0` to `c=Pn?0:eS+1` so Linux gets the 37px title bar offset like Windows
  - Updated `fix_title_bar.py`: Disables both early returns in renderer with `false&&` prefix instead of removing negation

## 2026-01-20

### Added
- **Multi-distro packaging** - Claude Desktop now available for multiple Linux distributions:
  - **AppImage** - Portable, runs on any distro without installation (bundles Electron)
  - **Debian/Ubuntu (.deb)** - Native package for apt-based systems
  - All formats built automatically in CI and uploaded to GitHub Releases
- **Pre-built package distribution** - CI now builds and uploads pre-patched tarballs to GitHub Releases:
  - Reduced dependencies for users (no python, asar, p7zip needed)
  - Faster package installation
  - Changelog included in GitHub release notes

### Changed
- **Refactored build architecture** - Separated patching logic from package generation:
  - New `scripts/build-patched-tarball.sh` contains all patching logic in one place
  - `PKGBUILD.template` is now a simple tarball-based installer (no patches)
  - `generate-pkgbuild.sh` simplified to just template substitution
  - CI builds tarball once, then builds AppImage/.deb/Flatpak from it
  - Users download pre-patched tarball (no build-time patching needed)
- **Electron version** - AppImage/Flatpak now fetch latest stable Electron automatically

## 2026-01-19

### Fixed
- **Patch patterns for v1.1.381** - Updated patches to use flexible regex patterns:
  - enable_local_agent_mode.py: Use `\w+` wildcard for minified function names (qWe→wYe, zWe→EYe)
  - fix_claude_code.py: Use regex with capture group for status enum name (Yo→tc)
  - fix_tray_icon_theme.py: Always use light tray icon on Linux (trays are universally dark)
  - fix_vm_session_handlers.py: Use regex patterns for all VM functions (WBe→Wme, Zc→Xc, IS→YS, ty→g0, qd→Qd, Qhe→Hme, Jhe→MB, ce→oe)

## 2026-01-13

### Added
- **Local Agent Mode for Linux** - New patch (enable_local_agent_mode.py) enables the "chillingSloth" feature on Linux:
  - Enables Local Agent Mode sessions with git worktree isolation
  - Enables Claude Code for Desktop integration
  - Patches qWe() and zWe() platform checks to return "supported" on all platforms
  - Note: SecureVM (yukonSilver) and Echo features still require macOS-only Swift modules
- **ClaudeVM Linux handling** - New patch (fix_vm_session_handlers.py) to gracefully handle VM features not supported on Linux:
  - getDownloadStatus returns NotDownloaded on Linux
  - getRunningStatus returns Offline on Linux
  - download/startVM fail with helpful error messages
  - Error handler suppresses unsupported feature errors

### Fixed
- **Claude Code Linux platform support** - Updated fix_claude_code.py to add Linux support:
  - Added Linux platform detection to getHostPlatform() (root cause of "Unsupported platform: linux-x64" error)
  - Linux checks now run BEFORE getHostTarget() to avoid throwing errors

## 2026-01-12

### Fixed
- **Patch patterns for v1.0.3218** - Updated patches to use flexible regex patterns:
  - fix_claude_code.py: Updated for new `getHostTarget()` and `binaryExistsForTarget()` APIs, status enum `Rv→Yo`
  - fix_app_quit.py: Use dynamic capture for variable names (`S_&&he→TS&&ce`)
  - fix_tray_dbus.py: Fix async check to avoid matching similar function names, handle preamble code before first const

## 2026-01-08

### Added
- **App quit fix** - Fix app not quitting after cleanup on Linux (fix_app_quit.py). After `will-quit` handler calls `preventDefault()`, `app.quit()` becomes a no-op. Solution uses `app.exit(0)` with `setImmediate` after cleanup completes.
- **UtilityProcess SIGKILL fix** - Use SIGKILL as fallback when UtilityProcess doesn't exit gracefully (fix_utility_process_kill.py)
- **Custom app icon** - Extract full-color orange Claude logo from setupIcon.ico at build time (requires icoutils)

### Fixed
- Fixed app hanging on exit when using integrated Node.js server for MCP

## 2025-12-17

### Added
- **MCP node host path fix** - Fix incorrect path for MCP server node host on Linux (fix_node_host.py)
- **Startup settings fix** - Handle Linux platform in startup settings to avoid validation errors (fix_startup_settings.py)
- **Tray icon theme fix** - Always use light tray icon on Linux since system trays are universally dark (fix_tray_icon_theme.py)

## 2025-12-02

### Fixed
- **Patch patterns for v1.0.1405** - Updated fix_quick_entry_position.py to use backreference pattern for fallback display variable (r→n)

## 2025-11-26

### Added
- **CLAUDE.md** - Patch debugging guidelines for developers

### Fixed
- **Patch patterns for v1.0.1307** - Updated fix_quick_entry_position.py and fix_tray_path.py to use flexible regex patterns (ce→de, pn→gn, pTe→lPe)

## 2025-11-25

### Added
- **Patch validation in CI pipeline** - Test build in Docker container before pushing to AUR
- **validate-patches.sh script** - Local validation tool for developers to test patches
- **Claude Code CLI integration** - Patch to detect and use system-installed `/usr/bin/claude`
- **AuthRequest stub** - Added AuthRequest class stub to claude-native.js for Linux authentication fallback
- **Native frame patch** - Use native window frames on Linux/XFCE while preserving Quick Entry transparency
- **Quick Entry position patch** - Spawn Quick Entry on the monitor where cursor is located
- **Tray DBus fix** - Prevent DBus race conditions with mutex guard and cleanup delay
- **Tray path fix** - Redirect tray icon path to package directory on Linux
- Isolated patch files in `patches/` directory for easier maintenance
- Local build script `scripts/build-local.sh` for development testing

### Changed
- **Patches now fail on pattern mismatch** - All Python patches exit with code 1 if patterns don't match
- **generate-pkgbuild.sh captures exit codes** - Build fails if any patch fails to apply
- Refactored all inline patches into separate files
- Refactored PKGBUILD generation to use template approach

### Fixed
- **Native frame patch** - Handle upstream code changes in v1.0.1217+ where main window no longer explicitly sets frame:false
- **Patch validation script** - Fixed handling of replace-type patches that create new files
- **CI pipeline** - Improved error handling with pipefail to catch build failures in piped commands
- Fixed tray icon loading - copy TrayIconTemplate PNG files to locales directory for Electron Tray API

### Removed
- Removed .SRCINFO from git tracking (auto-generated file)
- Removed PKGBUILD from repo (generated from template)

## 2025-11-24

### Changed
- Update to version 1.0.1217

## 2025-11-17

### Changed
- Update to version 1.0.734

## 2025-11-13

### Added
- Add GitHub repository link to PKGBUILD
- Add manual download URL input for workflow_dispatch

### Changed
- Update to version 1.0.332

## 2024-09-16

### Added
- Initial working package with patched claude-native module
- GitHub automation for AUR package maintenance
- Locale file loading patches for Linux compatibility
- Desktop entry and icon installation

### Fixed
- Title bar detection on Linux
- Tray icon functionality
- Notification support
