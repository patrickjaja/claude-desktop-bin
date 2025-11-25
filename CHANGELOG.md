# Changelog

All notable changes to claude-desktop-bin AUR package will be documented in this file.

## [Unreleased]

### Added
- **Claude Code CLI integration** - Patch to detect and use system-installed `/usr/bin/claude`
- **AuthRequest stub** - Added AuthRequest class stub to claude-native.js for Linux authentication fallback
- Isolated patch files in `patches/` directory for easier maintenance
- Local build script `scripts/build-local.sh` for development testing
- Version-specific filename for installer to prevent cache conflicts between updates

### Changed
- Refactored all inline patches into separate files:
  - `patches/claude-native.js` - Linux-compatible native module
  - `patches/fix_claude_code.py` - Claude Code CLI support
  - `patches/fix_locale_paths.py` - Locale file path fixes
  - `patches/fix_title_bar.py` - Title bar detection fix
- Refactored PKGBUILD generation to use template approach
- Installer files now include version number (e.g., `Claude-Setup-x64-0.13.19.exe`)

### Fixed
- Fixed PKGBUILD generation script - resolved menu display issue
- Fixed missing menu/title bar issue by replacing Rust binding with JavaScript implementation
- Fixed missing asar dependency in PKGBUILD
- Fixed tray icon loading - copy TrayIconTemplate PNG files to locales directory for Electron Tray API

### Removed
- Removed .SRCINFO from git tracking (auto-generated file)
- Removed PKGBUILD from repo (generated from template)

## [0.13.11] - 2024-09-16

### Added
- Initial working package with patched claude-native module
- GitHub automation for AUR package maintenance
- Locale file loading patches for Linux compatibility
- Desktop entry and icon installation

### Fixed
- Title bar detection on Linux
- Tray icon functionality
- Notification support