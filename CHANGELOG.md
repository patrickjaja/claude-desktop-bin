# Changelog

All notable changes to claude-desktop-bin AUR package will be documented in this file.

## [Unreleased]

### Added
- Version-specific filename for installer to prevent cache conflicts between updates

### Changed
- Refactored PKGBUILD generation to use template approach
- Installer files now include version number (e.g., `Claude-Setup-x64-0.13.19.exe`)

### Fixed
- Fixed PKGBUILD generation script - resolved menu display issue
- Fixed missing menu/title bar issue by replacing Rust binding with JavaScript implementation
- Fixed missing asar dependency in PKGBUILD

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