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
- Global hotkey support (Ctrl+Alt+Space)
- Automated daily version checks and AUR updates
- GitHub releases for version tracking

## Automation
This repository automatically:
- Checks for new Claude Desktop versions daily
- Updates the AUR package when new versions are detected
- Creates GitHub releases for tracking updates
- Maintains proper SHA256 checksums

## Repository Structure
- `.github/workflows/` - GitHub Actions for automation
- `scripts/` - Helper scripts for version detection and PKGBUILD generation
- `PKGBUILD` - Template for the AUR package (dynamically generated)

## Notes
- This is an unofficial package, not supported by Anthropic
- Report package-specific issues to this GitHub repository
- AUR package: https://aur.archlinux.org/packages/claude-desktop-bin
- Based on: https://github.com/k3d3/claude-desktop-linux-flake
