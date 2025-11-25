# Claude Desktop for Arch Linux / Manjaro

[![AUR version](https://img.shields.io/aur/version/claude-desktop-bin)](https://aur.archlinux.org/packages/claude-desktop-bin)
[![Update AUR Package](https://github.com/patrickjaja/claude-desktop-bin/actions/workflows/update-aur.yml/badge.svg)](https://github.com/patrickjaja/claude-desktop-bin/actions/workflows/update-aur.yml)

Unofficial AUR package for Claude Desktop AI assistant with automated updates.

## Installation

Using an AUR helper like yay:
```bash
yay -S claude-desktop-bin
```

Or manually:
```bash
git clone https://aur.archlinux.org/claude-desktop-bin.git
cd claude-desktop-bin
makepkg -si
```

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
| `fix_title_bar.py` | Fixes title bar detection issue on Linux |

When Claude Desktop updates break a patch, only the specific patch file needs updating.

## Automation
This repository automatically:
- Checks for new Claude Desktop versions daily
- Updates the AUR package when new versions are detected
- Creates GitHub releases for tracking updates
- Maintains proper SHA256 checksums

## Local Development Build

To build and test the package locally:
```bash
# Download Claude-Setup-x64.exe from https://claude.ai/download to project root
# Then run:
./scripts/build-local.sh

# Or build and install in one step:
./scripts/build-local.sh --install
```

## Repository Structure
- `.github/workflows/` - GitHub Actions for automation
- `scripts/` - Helper scripts for version detection and PKGBUILD generation
- `patches/` - Isolated patch files for Linux compatibility
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
