# Changelog

All notable changes to claude-desktop-bin AUR package will be documented in this file.

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
