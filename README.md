# Claude Desktop for Linux

[![AUR version](https://img.shields.io/aur/version/claude-desktop-bin)](https://aur.archlinux.org/packages/claude-desktop-bin)
[![Update AUR Package](https://github.com/patrickjaja/claude-desktop-bin/actions/workflows/update-aur.yml/badge.svg)](https://github.com/patrickjaja/claude-desktop-bin/actions/workflows/update-aur.yml)

Unofficial Linux packages for Claude Desktop AI assistant with automated updates.

## Installation

### Arch Linux / Manjaro (AUR)
```bash
yay -S claude-desktop-bin
```

### Debian / Ubuntu
```bash
# Download from GitHub Releases
wget https://github.com/patrickjaja/claude-desktop-bin/releases/latest/download/claude-desktop_1.1.2685_amd64.deb
sudo dpkg -i claude-desktop_*_amd64.deb
```

### AppImage (Any Distro)
```bash
# Download from GitHub Releases
wget https://github.com/patrickjaja/claude-desktop-bin/releases/latest/download/Claude_Desktop-1.1.2685-x86_64.AppImage
chmod +x Claude_Desktop-*-x86_64.AppImage
./Claude_Desktop-*-x86_64.AppImage
```

### From Source
```bash
git clone https://github.com/patrickjaja/claude-desktop-bin.git
cd claude-desktop-bin
./scripts/build-local.sh --install
```

## Features
- Native Linux support (Arch, Debian/Ubuntu, AppImage)
- **Claude Code CLI integration** - Auto-detects system-installed Claude Code
- **Local Agent Mode** - Git worktrees and agent sessions
- **MCP server support** - Model Context Protocol servers work on Linux
- Global hotkey support (Ctrl+Alt+Space) with multi-monitor awareness
- Automated daily version checks

## Claude Chat

The main Chat tab running natively on Linux.

![Claude Chat](cc.png)

## Claude Code Integration

This package patches Claude Desktop to work with system-installed Claude Code on Linux.

![Claude Code in Claude Desktop](cc_in_cd.png)

To use Claude Code (and Cowork) features, install the CLI following the [official setup guide](https://code.claude.com/docs/en/setup), then verify it's accessible:
```bash
which claude  # e.g. ~/.local/bin/claude, /usr/bin/claude, /usr/local/bin/claude
```

The patch auto-detects claude in `/usr/bin`, `~/.local/bin`, and `/usr/local/bin`.

## Cowork Integration (Experimental)

Cowork is Claude Desktop's agentic workspace feature. This package patches it to work on Linux using a native backend daemon instead of the macOS/Windows VM.

![Cowork in Claude Desktop](co_in_cd.png)

Requires Claude Code CLI (see above) and [claude-cowork-service](https://github.com/patrickjaja/claude-cowork-service):

**Any distro (quick install):**
```bash
curl -fsSL https://raw.githubusercontent.com/patrickjaja/claude-cowork-service/main/scripts/install.sh | bash
```

**Arch Linux (AUR):**
```bash
yay -S claude-cowork-service
systemctl --user enable --now claude-cowork
```

## Patches

The package applies several patches to make Claude Desktop work on Linux. Each patch is isolated in `patches/` for easy maintenance:

| Patch | Purpose |
|-------|---------|
| `claude-native.js` | Linux-compatible native module (replaces Windows-only `@anthropic/claude-native`) |
| `enable_local_agent_mode.py` | Enables Local Agent Mode (chillingSlothFeat) on Linux for git worktrees and agent sessions |
| `fix_claude_code.py` | Enables Claude Code CLI integration by detecting system-installed claude binary |
| `fix_locale_paths.py` | Redirects locale file paths to Linux install location |
| `fix_node_host.py` | Fixes MCP server node host path for Linux (uses `app.getAppPath()`) |
| `fix_startup_settings.py` | Skips startup settings on Linux to avoid validation errors |
| `fix_native_frame.py` | Uses native window frames on Linux/XFCE while preserving Quick Entry transparency |
| `fix_quick_entry_position.py` | Spawns Quick Entry window on the monitor where the cursor is located |
| `fix_title_bar.py` | Renders internal title bar on Linux (disables platform-gated early returns) |
| `fix_tray_dbus.py` | Prevents DBus race conditions with mutex guard and cleanup delay |
| `fix_tray_icon_theme.py` | Uses theme-aware tray icon selection (light/dark) on Linux |
| `fix_tray_path.py` | Redirects tray icon path to package directory on Linux |
| `fix_cowork_linux.py` | Enables Cowork on Linux: VM client loader, Unix socket path, bundle config, claude binary resolution |
| `fix_cowork_error_message.py` | Replaces Windows VM errors with Linux-friendly guidance for claude-cowork-service |
| `fix_cross_device_rename.py` | Fixes EXDEV errors when moving VM bundles across filesystems (tmpfs to ext4) |
| `fix_vm_session_handlers.py` | Global uncaught exception handler for VM session safety |
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

## Repository Structure
- `.github/workflows/` - GitHub Actions for automation
- `scripts/` - Build and validation scripts
- `patches/` - Linux compatibility patches
- `packaging/` - Debian and AppImage build scripts
- `PKGBUILD.template` - AUR package template

## Wayland: Global Shortcut Not Working

On pure Wayland compositors (e.g. Hyprland, Sway), the Quick Entry shortcut (Ctrl+Alt+Space) doesn't work because Electron's `globalShortcut` relies on X11. Force XWayland mode to fix it:

```bash
claude-desktop --ozone-platform=x11
```

To make it persistent, edit `~/.local/share/applications/claude-desktop.desktop`:
```ini
Exec=claude-desktop --ozone-platform=x11 %u
```

## Tips
- Press **Alt** to toggle the app menu bar (Electron default)

## Notes
- Unofficial package, not supported by Anthropic
- Issues: https://github.com/patrickjaja/claude-desktop-bin/issues
- Based on: https://github.com/k3d3/claude-desktop-linux-flake
