# Claude Desktop for Linux

[![AUR version](https://img.shields.io/aur/version/claude-desktop-bin)](https://aur.archlinux.org/packages/claude-desktop-bin)
[![Update AUR Package](https://github.com/patrickjaja/claude-desktop-bin/actions/workflows/update-aur.yml/badge.svg)](https://github.com/patrickjaja/claude-desktop-bin/actions/workflows/update-aur.yml)

Unofficial Linux packages for Claude Desktop AI assistant with automated updates.

## Installation

### Arch Linux / Manjaro (AUR)
```bash
yay -S claude-desktop-bin
```
Updates arrive through your AUR helper (e.g. `yay -Syu`).

### Debian / Ubuntu (APT Repository)
```bash
# Add repository (one-time setup)
curl -fsSL https://patrickjaja.github.io/claude-desktop-bin/install.sh | sudo bash

# Install
sudo apt install claude-desktop-bin
```
Updates are automatic via `sudo apt update && sudo apt upgrade`.

<details>
<summary>Manual .deb install (without APT repo)</summary>

```bash
wget https://github.com/patrickjaja/claude-desktop-bin/releases/latest/download/claude-desktop-bin_1.1.8359-2_amd64.deb
sudo dpkg -i claude-desktop-bin_*_amd64.deb
```
</details>

### Fedora / RHEL (.rpm)
```bash
# Download from GitHub Releases
wget https://github.com/patrickjaja/claude-desktop-bin/releases/latest/download/claude-desktop-bin-1.1.8359-2.x86_64.rpm
sudo dnf install ./claude-desktop-bin-*.x86_64.rpm
```

> **Note:** No automatic updates. Download the latest `.rpm` from [GitHub Releases](https://github.com/patrickjaja/claude-desktop-bin/releases) to update.

### NixOS / Nix
```bash
# Try without installing
nix run github:patrickjaja/claude-desktop-bin

# Or add to flake.nix
nix profile install github:patrickjaja/claude-desktop-bin
```

<details>
<summary>NixOS flake configuration</summary>

```nix
{
  inputs.claude-desktop.url = "github:patrickjaja/claude-desktop-bin";

  # In your system config:
  environment.systemPackages = [
    inputs.claude-desktop.packages.x86_64-linux.default
  ];
}
```
</details>

> **Note:** Update by running `nix flake update` to pull the latest version. `nix run` always fetches the latest.

### AppImage (Any Distro)
```bash
# Download from GitHub Releases
wget https://github.com/patrickjaja/claude-desktop-bin/releases/latest/download/Claude_Desktop-1.1.8359-x86_64.AppImage
chmod +x Claude_Desktop-*-x86_64.AppImage
./Claude_Desktop-*-x86_64.AppImage
```

> **Note:** AppImage does not receive automatic updates. Download the latest release manually to update.

### From Source
```bash
git clone https://github.com/patrickjaja/claude-desktop-bin.git
cd claude-desktop-bin
./scripts/build-local.sh --install
```

> **Note:** Source builds do not receive automatic updates. Pull and rebuild to update.

## Features
- Native Linux support (Arch, Debian/Ubuntu, Fedora/RHEL, NixOS, AppImage)
- **Claude Code CLI integration** - Auto-detects system-installed Claude Code (requires [claude-code](https://code.claude.com/docs/en/setup))
- **Local Agent Mode** - Git worktrees and agent sessions
- **Cowork support** - Agentic workspace feature enabled on Linux (requires [claude-cowork-service](https://github.com/patrickjaja/claude-cowork-service))
- **Computer Use** - Desktop automation via built-in MCP server (screenshot, click, type, scroll, drag, clipboard). Uses `xdotool` for input, `scrot` for screenshots, `xclip` for clipboard. No macOS-style permission grants needed — all tools work immediately. Install: `sudo pacman -S xdotool scrot xclip wmctrl`
- **Dispatch** - Send tasks from your phone to your desktop Claude via Anthropic's environments bridge API (requires Cowork). Text responses, task orchestration, and SDK MCP tools work. Bridge-level transform wraps plain text as `SendUserMessage` (workaround for CLI 2.1.x bug where `--brief` doesn't expose the tool)
- **MCP server support** - Model Context Protocol servers work on Linux
- **Custom Themes (Experimental)** - 6 built-in color themes (Nord, Catppuccin Mocha/Frappe/Latte/Macchiato, Sweet) or create your own via JSON config — not all UI elements are fully themed yet
- **Multi-monitor Quick Entry** - Global hotkey (Ctrl+Alt+Space) opens on the monitor where your cursor is ([Wayland notes](#wayland))
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

## CoworkSpaces

CoworkSpaces organizes folders, projects, and links into named Spaces for Cowork sessions. On macOS/Windows this is handled by the native backend (`@ant/claude-swift`). On Linux, `fix_cowork_spaces.py` provides a full file-based implementation:

- Stores spaces in `~/.config/Claude/spaces.json`
- Full CRUD: create, update, delete spaces with folders, projects, and links
- File operations: list folder contents, read files, open with system handler
- Auto-memory directories per space (`~/.config/Claude/spaces/<id>/memory/`)
- Integrates with the SpaceManager singleton so `resolveSpaceContext` works for sessions

The Spaces UI is rendered by the claude.ai web frontend (loaded in the BrowserView).

## Custom Themes (Experimental)

Themes override CSS variables in **all windows** (main chat, Quick Entry, Find-in-Page, About) via Electron's `insertCSS()` API. Set Claude Desktop to **dark mode** for best results with dark themes.

**Quick start:**
```bash
echo '{"activeTheme": "sweet"}' > ~/.config/Claude/claude-desktop-bin.json
# Restart Claude Desktop
```

**Built-in themes:** `sweet`, `nord`, `catppuccin-mocha`, `catppuccin-frappe`, `catppuccin-latte`, `catppuccin-macchiato`

| Sweet | Nord | Catppuccin Mocha |
|-------|------|------------------|
| Purple/pink warm tones ([github.com/EliverLara/Sweet](https://github.com/EliverLara/Sweet)) | Arctic blue-grey ([nordtheme.com](https://nordtheme.com)) | Warm pastels ([catppuccin.com](https://catppuccin.com)) |

See **[themes/README.md](themes/README.md)** for the full theming guide: CSS variable reference, how to extract app HTML/CSS for inspection, custom theme creation, and screenshots.

## Patches

The package applies several patches to make Claude Desktop work on Linux. Each patch is isolated in `patches/` for easy maintenance:

| Patch | Purpose | Break risk | Debug pattern |
|-------|---------|------------|---------------|
| `add_feature_custom_themes.py` | Custom CSS theme injection via `insertCSS()` — 6 built-in themes (sweet, nord, catppuccin-*) | VERY LOW | Prepended IIFE, no regex on app code |
| `claude-native.js` | Linux-compatible native module (replaces Windows-only `@anthropic/claude-native`) | LOW | Static file, no regex |
| `enable_local_agent_mode.py` | Enables Local Agent Mode (chillingSlothFeat) on Linux for git worktrees and agent sessions | HIGH | `rg -o 'function \w+\(\)\{return process\.platform.*status' index.js` |
| `fix_0_node_host.py` | Fixes MCP server node host path for Linux (uses `app.getAppPath()`) | LOW | `rg -o 'nodeHostPath.{0,50}' index.js` |
| `fix_app_quit.py` | Fixes app not quitting after cleanup on Linux (uses `app.exit(0)` instead of `app.quit()`) | LOW | Uses `app.quit()` literal |
| `fix_browse_files_linux.py` | Enables `openDirectory` in browseFiles dialog on Linux (Electron supports it, upstream only enabled for macOS) | LOW | `rg -o 'openDirectory.{0,60}' index.js` |
| `fix_claude_code.py` | Enables Claude Code CLI integration by detecting system-installed claude binary | MED | `rg -o 'async getStatus\(\)\{.{0,200}' index.js` |
| `fix_computer_use_linux.py` | Enables Computer Use on Linux: removes 3 platform gates, provides xdotool/scrot executor, bypasses macOS permission model | MED | `rg -o 'process.platform.*darwin.*t7r' index.js` |
| `fix_computer_use_tcc.py` | Registers no-op IPC handlers for macOS TCC permission checks — prevents repeated error logs | LOW | Uses eipc UUID extraction |
| `fix_cowork_error_message.py` | Replaces Windows VM errors with Linux-friendly guidance for claude-cowork-service | LOW | Uses string literals |
| `fix_cowork_linux.py` | Enables Cowork on Linux: VM client loader, Unix socket path, bundle config, claude binary resolution | HIGH | `rg -o '.{0,50}vmClient.{0,50}' index.js` |
| `fix_cowork_spaces.py` | Stubs CoworkSpaces eipc handlers on Linux (getAllSpaces, createSpace, etc.) | LOW | `rg -o 'CoworkSpaces' index.js` |
| `fix_cross_device_rename.py` | Fixes EXDEV errors when moving VM bundles across filesystems (tmpfs to ext4) | LOW | Uses `.rename(` literal |
| `fix_detected_projects_linux.py` | Enable detected projects on Linux (VSCode/Cursor/Zed path mapping) | MED | `rg -o 'detectedProjects.{0,50}' index.js` |
| `fix_disable_autoupdate.py` | Disables auto-updater on Linux (no Windows installer available) | MED | `rg -o '.{0,40}isInstalled.{0,40}' index.js` |
| `fix_dispatch_linux.py` | Enables Dispatch (remote task orchestration from mobile) — forces bridge init, bypasses remote control gate, adds Linux platform label, transforms text→SendUserMessage | MED | `rg -o 'sessions-bridge.*init' index.js` |
| `fix_dock_bounce.py` | Prevents taskbar attention-stealing on KDE Plasma/Linux — intercepts `flashFrame`, `focus`, `show`, `moveTop`, and `WebContents.focus()` | LOW | Prepended IIFE, no regex on app code |
| `fix_locale_paths.py` | Redirects locale file paths to Linux install location | LOW | Uses `process.resourcesPath` literal |
| `fix_enterprise_config_linux.py` | Reads enterprise config from `/etc/claude-desktop/enterprise.json` on Linux (disableAutoUpdates, custom3p, DXT flags, etc.) | LOW | `rg -o 'enterprise.json' index.js` |
| `fix_marketplace_linux.py` | Forces CCD mode for marketplace plugin operations on Linux (no VM, use host-local paths) | MED | `rg -o 'function \w+\(\w+\)\{return\(\w+==null.*mode.*ccd' index.js` |
| `fix_native_frame.py` | Uses native window frames on Linux/XFCE while preserving Quick Entry transparency | MED | `rg -o 'titleBarStyle.{0,30}' index.js` |
| `fix_office_addin_linux.py` | Enables Office Addin MCP server on Linux — extends `(ui\|\|as)` platform gate in isEnabled, init block, and file detection | LOW | `rg -o '.{0,30}louderPenguinEnabled.{0,30}' index.js` |
| `fix_process_argv_renderer.py` | Injects `process.argv=[]` in renderer preload to prevent TypeError on `.includes()` calls | LOW | `rg -o '.{0,30}\.argv.{0,30}' mainView.js` |
| `fix_quick_entry_position.py` | Spawns Quick Entry window on the monitor where the cursor is located | MED | `rg -o 'getPrimaryDisplay.{0,50}' index.js` |
| `fix_read_terminal_linux.py` | Enables `read_terminal` built-in MCP server on Linux (was hardcoded darwin-only) | LOW | `rg -o 'read_terminal.{0,100}' index.js` |
| `fix_startup_settings.py` | Skips startup settings on Linux to avoid validation errors | LOW | `rg -o 'isStartupOnLoginEnabled.{0,50}' index.js` |
| `fix_tray_dbus.py` | Prevents DBus race conditions with mutex guard and cleanup delay | HIGH | `rg -o 'menuBarEnabled.*function' index.js` |
| `fix_tray_icon_theme.py` | Uses theme-aware tray icon selection (light/dark) on Linux | LOW | `rg -o 'nativeTheme.{0,50}tray' index.js` |
| `fix_tray_path.py` | Redirects tray icon path to package directory on Linux | MED | `rg -o 'function \w+\(\)\{return \w+\.app\.isPackaged' index.js` |
| `fix_updater_state_linux.py` | Adds `version`/`versionNumber` to idle updater state to prevent `.includes()` TypeError | LOW | `rg -o 'status:"idle".{0,50}' index.js` |
| `fix_utility_process_kill.py` | Uses SIGKILL as fallback when UtilityProcess doesn't exit gracefully | LOW | Uses `.kill(` literal |
| `fix_vm_session_handlers.py` | Global uncaught exception handler for VM session safety | LOW | `rg -o 'uncaughtException.{0,50}' index.js` |
| `fix_window_bounds.py` | Fixes child view bounds on maximize/KWin snap, ready-to-show layout jiggle, Quick Entry blur-before-hide | LOW | Injected IIFE, no regex on app code |

When Claude Desktop updates break a patch, only the specific patch file needs updating. The **debug pattern** column shows the `rg` command to find the relevant code in the new version's `index.js`.

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
- `packaging/` - Debian, RPM, AppImage, and Nix build scripts
- `PKGBUILD.template` - AUR package template

## Wayland

Claude Desktop defaults to XWayland mode, which is recommended. If you use native Wayland (`CLAUDE_USE_WAYLAND=1`), global shortcuts (Ctrl+Alt+Space) and window positioning won't work — these require X11. Stick with XWayland for full functionality.

## Debugging

Launch Claude Desktop with DevTools auto-opened:
```bash
CLAUDE_DEV_TOOLS=detach claude-desktop
```

This opens a detached Chromium DevTools window where you can:
- **Console** — view JavaScript errors and logs
- **Network** — inspect API requests (check EventStream on `/completion` requests for streaming errors)
- **Application** — inspect local storage, cookies, session data

To also capture Electron main process logs to a file:
```bash
CLAUDE_DEV_TOOLS=detach ELECTRON_ENABLE_LOGGING=1 claude-desktop 2>&1 | tee /tmp/claude-debug.log
```

Runtime logs are written to `~/.config/Claude/logs/`:
| Log File | Description |
|----------|-------------|
| `main.log` | Main Electron process |
| `claude.ai-web.log` | BrowserView web content |
| `mcp.log` | MCP server communication |

```bash
# Tail logs in real-time
tail -f ~/.config/Claude/logs/main.log

# Search for errors across all logs
grep -ri 'error\|exception\|fatal' ~/.config/Claude/logs/
```

### Clear Dispatch session

Dispatch reuses a persistent session transcript. If the model encountered errors in previous turns (e.g. "Permission denied" for a tool, or broken responses), it remembers those failures and may refuse to retry. Clear the session to start fresh:

```bash
# Find your dispatch session directory
ls ~/.config/Claude/local-agent-mode-sessions/

# Remove the dispatch agent session (replace UUIDs with your own)
rm -rf ~/.config/Claude/local-agent-mode-sessions/<account-uuid>/<org-uuid>/agent/local_ditto_*/

# Then restart Claude Desktop
```

You can identify your UUIDs from the directory listing — there's typically one account directory containing one org directory.

## Known Issues (Dispatch)

These issues are caused by a regression in Claude Code CLI v2.1.79+ where the `SendUserMessage` tool is not exposed to the model. On Windows/Mac, the cowork VM bundles CLI v2.1.78 (via Agent SDK 0.2.78) where this works. On Linux, the system-installed CLI has the bug. Tracked upstream: [anthropics/claude-code#35076](https://github.com/anthropics/claude-code/issues/35076)

| Issue | Status | Detail |
|-------|--------|--------|
| Dispatch text responses not rendering | **Workaround active** | Patch I wraps plain text as synthetic `SendUserMessage` tool_use blocks. Responses render on phone/desktop. |
| File attachments load endlessly on phone | **Not yet fixed** | The model can't use `SendUserMessage` with `attachments`, so files aren't uploaded via the dispatch file API. Will resolve when the CLI exposes `SendUserMessage` natively. |

Both issues resolve when Anthropic fixes the CLI initialization ordering so `--brief` properly exposes `SendUserMessage`. We're monitoring upstream.

## Known Limitations

| Feature | Detail |
|---------|--------|
| **Browser Tools (Chrome integration)** | Not available on Linux. The Chrome Extension MCP server requires a native messaging host binary (`chrome-native-host`) that Anthropic ships only for Windows/macOS (Rust, proprietary). A Linux replacement would need to implement Chrome's Native Messaging protocol. Contributions welcome. |

## Tips
- Press **Alt** to toggle the app menu bar (Electron default)

## See Also

- [tweakcc](https://github.com/Piebald-AI/tweakcc) — A great CLI tool for customizing Claude Code (system prompts, themes, UI). Same patching-JS-to-make-it-yours energy. Thanks to the Piebald team for their work.

## Legal Notice

> This is an **unofficial community project** for educational and research purposes.
> Claude Desktop is proprietary software owned by **Anthropic PBC**.
>
> This repository contains only build scripts and patches — not the Claude Desktop
> application itself. The upstream binary is downloaded directly from Anthropic
> during the build process.
>
> This project is not affiliated with, endorsed by, or sponsored by Anthropic.
> "Claude" is a trademark of Anthropic PBC.
