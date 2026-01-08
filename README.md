# Claude Desktop for Arch Linux / Manjaro

[![AUR version](https://img.shields.io/aur/version/claude-desktop-bin)](https://aur.archlinux.org/packages/claude-desktop-bin)
[![Update AUR Package](https://github.com/patrickjaja/claude-desktop-bin/actions/workflows/update-aur.yml/badge.svg)](https://github.com/patrickjaja/claude-desktop-bin/actions/workflows/update-aur.yml)

Unofficial AUR package for Claude Desktop AI assistant with automated updates.

## Installation

Using an AUR helper like yay:
```bash
yay -S claude-desktop-bin
```

For a fresh installation (clears cached builds):
```bash
rm -rf ~/.cache/yay/claude-desktop-bin
yay -S claude-desktop-bin --noconfirm --cleanafter
```

Or manually from GitHub:
```bash
git clone https://github.com/patrickjaja/claude-desktop-bin.git
cd claude-desktop-bin
./scripts/build-local.sh --install
```

Note: The script will automatically download the installer. Alternatively, download `Claude-Setup-x64.exe` from https://claude.ai/download to the project root before running.

## Features
- Native Linux support
- **Claude Code CLI integration** - Use system-installed Claude Code (`/usr/bin/claude`)
- Global hotkey support (Ctrl+Alt+Space)
- Automated daily version checks and AUR updates
- GitHub releases for version tracking

## Claude Code Integration

This package patches Claude Desktop to work with system-installed Claude Code on Linux.

![Claude Code CLI](cc.png)
![Claude Code in Claude Desktop](cc_in_cd.png)

To use Claude Code features:
```bash
# Install Claude Code CLI via npm
npm install -g @anthropic-ai/claude-code

# Verify it's accessible
which claude  # Should show /usr/bin/claude or similar
```

## Patches

The package applies several patches to make Claude Desktop work on Linux. Each patch is isolated in `patches/` for easy maintenance:

| Patch | Purpose |
|-------|---------|
| `claude-native.js` | Linux-compatible native module (replaces Windows-only `@anthropic/claude-native`) |
| `fix_claude_code.py` | Enables Claude Code CLI integration by detecting `/usr/bin/claude` |
| `fix_locale_paths.py` | Redirects locale file paths to Linux install location |
| `fix_node_host.py` | Fixes MCP server node host path for Linux (uses `app.getAppPath()`) |
| `fix_startup_settings.py` | Skips startup settings on Linux to avoid validation errors |
| `fix_title_bar.py` | Shows internal title bar on Linux (hamburger menu, Claude icon) |
| `fix_native_frame.py` | Uses native window frames on Linux/XFCE while preserving Quick Entry transparency |
| `fix_quick_entry_position.py` | Spawns Quick Entry window on the monitor where the cursor is located |
| `fix_tray_dbus.py` | Prevents DBus race conditions with mutex guard and cleanup delay |
| `fix_tray_icon_theme.py` | Uses theme-aware tray icon selection (light/dark) on Linux |
| `fix_tray_path.py` | Redirects tray icon path to package directory on Linux |
| `fix_app_quit.py` | Fixes app not quitting after cleanup on Linux (uses `app.exit(0)` instead of `app.quit()`) |
| `fix_utility_process_kill.py` | Uses SIGKILL as fallback when UtilityProcess doesn't exit gracefully |

When Claude Desktop updates break a patch, only the specific patch file needs updating.

## Automation
This repository automatically:
- Checks for new Claude Desktop versions daily
- **Validates all patches in Docker** before pushing to AUR
- Updates the AUR package when new versions are detected
- Creates GitHub releases for tracking updates
- Maintains proper SHA256 checksums

### Patch Validation

The CI pipeline includes a test build step that validates patches before updating AUR:

1. **Docker Test Build** - Runs `makepkg` in an `archlinux:base-devel` container
2. **Pattern Matching Validation** - Each patch exits with code 1 if patterns don't match
3. **Pipeline Stops on Failure** - Broken packages never reach AUR users
4. **Build Logs Uploaded** - Artifacts available for debugging failures

If upstream Claude Desktop changes break a patch:
- The pipeline fails with clear `[FAIL]` output
- Build logs show which pattern didn't match
- AUR package remains unchanged until patches are updated

## Local Development Build

To build and test the package locally:
```bash
# Download Claude-Setup-x64.exe from https://claude.ai/download to project root
# Then run:
./scripts/build-local.sh

# Or build and install in one step:
./scripts/build-local.sh --install
```

### Validating Patches Locally

Before committing patch changes, validate them against an extracted app:
```bash
# Extract the app.asar
asar extract app.asar app.asar.contents

# Run validation
./scripts/validate-patches.sh ./app.asar.contents
```

Example output:
```
=== Patch Validation Report ===
[fix_claude_code.py]
  Target: app.asar.contents/.vite/build/index.js
  [OK] getBinaryPathIfReady(): 1 match(es)
  [OK] getStatus(): 1 match(es)
  Status: PASS
...
Summary: 7 passed, 0 failed
```

## Repository Structure
- `.github/workflows/` - GitHub Actions for automation
- `scripts/` - Helper scripts for version detection, PKGBUILD generation, and validation
  - `build-local.sh` - Build package locally
  - `extract-version.sh` - Extract version from Windows installer
  - `generate-pkgbuild.sh` - Generate PKGBUILD from template
  - `validate-patches.sh` - Validate patches against extracted app
- `patches/` - Isolated patch files for Linux compatibility
- `PKGBUILD.template` - Template for generating PKGBUILD
- `PKGBUILD` - Dynamically generated (not stored in repo)

## Development

### Git Remotes
This repository uses two git remotes:
```bash
# GitHub remote (main repository)
git remote add github git@github.com:patrickjaja/claude-desktop-bin.git

# AUR remote (for package updates)
git remote add aur https://aur.archlinux.org/claude-desktop-bin.git
```

To push changes to GitHub:
```bash
git push github master
```

The AUR package is automatically updated via GitHub Actions workflow.

## Notes
- This is an unofficial package, not supported by Anthropic
- Report package-specific issues to this GitHub repository
- AUR package: https://aur.archlinux.org/packages/claude-desktop-bin
- Based on: https://github.com/k3d3/claude-desktop-linux-flake
