# Changelog

All notable changes to claude-desktop-bin AUR package will be documented in this file.

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
