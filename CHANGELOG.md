# Changelog

All notable changes to claude-desktop-bin AUR package will be documented in this file.

## 2026-03-24 (v1.1.8359)

### Added
- **fix_computer_use_linux.py** — New patch: enables Computer Use on Linux with 6 sub-patches. Removes 3 upstream platform gates (`b7r()`, `ZM()`, `createDarwinExecutor`), provides a Linux executor using xdotool/scrot/xclip/wmctrl, bypasses macOS TCC permissions (`ensureOsPermissions` returns granted), and replaces the macOS permission model (`rvr()` allowlist/tier system) with direct tool dispatch. 22 tools work immediately without `request_access` — no app tier restrictions, no bundle ID matching, no permission dialogs.

### Changed
- **All existing patches pass cleanly** — No patch code changes needed for v1.1.8359 (up from v1.1.8308).
- **CLAUDE_BUILT_IN_MCP.md** — Updated to v1.1.8359. Added Computer Use as Server #14 with full Linux executor documentation, 22-tool table, 6 sub-patch table, Linux tools table, and key differences from macOS.
- **README.md** — Added Computer Use to features section. Added `fix_computer_use_linux.py` to patches table. Updated version references to v1.1.8359.
- **PKGBUILD.template** — Added `scrot`, `xclip`, `wmctrl` as optional dependencies for computer-use.
- **packaging/debian/control** — Added `scrot`, `xclip`, `wmctrl` to Suggests.
- **packaging/rpm/claude-desktop-bin.spec** — Added `scrot`, `xclip`, `wmctrl` to Suggests.
- **packaging/nix/package.nix** — Added `scrot`, `xclip`, `wmctrl` as optional inputs with PATH prefixes.

### Notes
- **Computer Use MCP is back** — Removed in v1.1.7714 (commit 2c69b13) when upstream dropped the standalone `computer-use-server.js`. Now reintroduced as a built-in internal MCP server integrated into `index.js`. Upstream gates it to macOS-only (`@ant/claude-swift`); our patch provides a Linux-native implementation. Key architectural decision: upstream's macOS permission model (app tiers, allowlists, TCC) is bypassed entirely on Linux since xdotool can interact with any window freely.
- **No new platform gates** — No other new `process.platform` restrictions found requiring patches.

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
