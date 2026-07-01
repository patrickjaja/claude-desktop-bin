# Claude Desktop for Linux

[![Claude Desktop](https://img.shields.io/endpoint?url=https://patrickjaja.github.io/claude-desktop-bin/badges/version-check.json)](https://claude.ai/download)
[![Build & Release](https://github.com/patrickjaja/claude-desktop-bin/actions/workflows/build-and-release.yml/badge.svg)](https://github.com/patrickjaja/claude-desktop-bin/actions/workflows/build-and-release.yml)
[![Website](https://img.shields.io/badge/Website-Landing_Page-a78bfa?logo=github)](https://patrickjaja.github.io/claude-desktop-bin/)
[![Reddit](https://img.shields.io/badge/Reddit-Discussion-FF4500?logo=reddit&logoColor=white)](https://www.reddit.com/r/ClaudeAI/comments/1r871b0/claude_desktop_on_linux_chat_cowork_code/)

[![AUR version](https://img.shields.io/aur/version/claude-desktop-bin)](https://aur.archlinux.org/packages/claude-desktop-bin)
[![APT repo](https://img.shields.io/endpoint?url=https://patrickjaja.github.io/claude-desktop-bin/badges/apt-repo.json)](https://github.com/patrickjaja/claude-desktop-bin#debian--ubuntu-apt-repository)
[![RPM repo](https://img.shields.io/endpoint?url=https://patrickjaja.github.io/claude-desktop-bin/badges/rpm-repo.json)](https://github.com/patrickjaja/claude-desktop-bin#fedora--rhel-dnf-repository)
[![AppImage](https://img.shields.io/endpoint?url=https://patrickjaja.github.io/claude-desktop-bin/badges/appimage.json)](https://github.com/patrickjaja/claude-desktop-bin#appimage-any-distro)
[![Nix flake](https://img.shields.io/endpoint?url=https://patrickjaja.github.io/claude-desktop-bin/badges/nix.json)](https://github.com/patrickjaja/claude-desktop-bin#nixos--nix)

**Anthropic's official Claude Desktop Linux build, repackaged for the distros Anthropic doesn't ship - plus Linux-only extras.**

Anthropic publishes an official Claude Desktop [Linux `.deb`](https://code.claude.com/docs/en/desktop-linux) (Ubuntu 22.04+ / Debian 12+, amd64 + arm64). This project takes that official build, repackages it for **Arch/AUR, Fedora/RHEL, NixOS, and AppImage** (and offers its own Debian/Ubuntu `.deb`), and layers on four Linux-only value-adds the official build lacks:

- [**Computer Use**](#computer-use) - desktop automation (screenshot, click, type, scroll, teach mode). Not in the official Linux beta - **our own implementation.**
- [**Custom Themes**](#custom-themes) - 7 built-in dual light/dark themes with custom loading spinners, or roll your own.
- [**Multiple Profiles**](#multiple-profiles) - run several instances side by side, each logged in to a different account with fully isolated state.
- [**Quick Entry**](#quick-entry) - global hotkey popup (Ctrl+Alt+Space), multi-monitor and Wayland-aware.

Everything else - Chat, Claude Code, Cowork, Browser Tools, 3P/enterprise inference - is the **official upstream build working natively on Linux**, preserved through the repackage. On top of that we ship a batch of **Linux fixes** for problems reported by real users: Cowork "Download failed" on Arch/Fedora, MCP servers failing, false memory-pressure warnings, exit hangs, white screens on some GPUs, plus enabling upstream features that are gated off or macOS-only on Linux (Dispatch, Browser Tools, "Open in editor", and more). See the [Patches](#patches) table for the full list. As Anthropic ships these fixes natively, we retire the matching patch - so this set shrinks over time as the official build catches up.

> **If you run Ubuntu 22.04+ / Debian 12+,** Anthropic's [official `.deb`](https://code.claude.com/docs/en/desktop-linux) installs the base app directly. Use this project if you're on Arch/Fedora/RHEL/Nix/AppImage, or if you want the four value-adds and Linux fixes above.

<details>
<summary><b>Table of contents</b></summary>

- [Installation](#installation)
- [Computer Use](#computer-use)
- [Computer Use dependencies](#computer-use-dependencies)
- [Custom Themes](#custom-themes)
- [Multiple Profiles](#multiple-profiles)
- [Quick Entry](#quick-entry)
- [Cowork setup (needs /dev/kvm)](#cowork-setup-needs-devkvm)
- [Third-Party / Enterprise Inference](#third-party--enterprise-inference)
- [Patches](#patches)
- [Command-line flags](#command-line-flags)
- [Environment Variables](#environment-variables)
- [Debugging](#debugging)
- [Known Limitations](#known-limitations)
- [Automation](#automation)
- [Repository Structure](#repository-structure)
- [See Also](#see-also)
- [Legal Notice](#legal-notice)

</details>

## Installation

> After installing, see [Computer Use dependencies](#computer-use-dependencies) and [Cowork setup](#cowork-setup-needs-devkvm) to enable those features.

### Arch Linux / Manjaro (AUR)
```bash
yay -S claude-desktop-bin
```
Updates arrive through your AUR helper (e.g. `yay -Syu`).

### Debian / Ubuntu (APT Repository)

> **Requires Ubuntu 22.04+ / Debian 12+** (glibc 2.34 or newer). Debian 11 (bullseye) is no longer supported.

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
wget https://github.com/patrickjaja/claude-desktop-bin/releases/latest/download/claude-desktop-bin_1.17282.0-1_amd64.deb
sudo dpkg -i claude-desktop-bin_*_amd64.deb
```
</details>

### Fedora / RHEL (DNF Repository)
```bash
# Add repository (one-time setup)
curl -fsSL https://patrickjaja.github.io/claude-desktop-bin/install-rpm.sh | sudo bash

# Install
sudo dnf install claude-desktop-bin
```
Updates are automatic via `sudo dnf upgrade`.

<details>
<summary>Manual .rpm install (without DNF repo)</summary>

```bash
wget https://github.com/patrickjaja/claude-desktop-bin/releases/latest/download/claude-desktop-bin-1.17282.0-1.x86_64.rpm
sudo dnf install ./claude-desktop-bin-*.x86_64.rpm
```
</details>

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

> **Computer Use / Dispatch on Nix:** pass optional dependencies via `.override { … }`, and if nixpkgs ships an older Claude Code (< 2.1.86) point at your own with `extraSessionPaths = [ "/path/to/dir/with/claude" ]`. See [Computer Use dependencies](#computer-use-dependencies).

### AppImage (Any Distro)

Works on standard and **immutable/atomic distros** - Bazzite, Fedora Silverblue/Kinoite, SteamOS, Universal Blue, NixOS (without the Nix package), and any other glibc-based Linux.

The `claude://` protocol handler (needed for OAuth sign-in) is **automatically registered** on first launch. If you move or rename the AppImage, the registration updates on the next launch.

```bash
# Download from GitHub Releases
wget https://github.com/patrickjaja/claude-desktop-bin/releases/latest/download/Claude_Desktop-1.17282.0-x86_64.AppImage
chmod +x Claude_Desktop-*-x86_64.AppImage
./Claude_Desktop-*-x86_64.AppImage
```

> **Update:** AppImage supports delta updates via [appimagetool](https://github.com/AppImageCommunity/AppImageUpdate) - only changed blocks are downloaded (`appimageupdatetool Claude_Desktop-*.AppImage`, or `--appimage-update` from within). Compatible with [AppImageLauncher](https://github.com/TheAssassin/AppImageLauncher) and [Gear Lever](https://github.com/mijorus/gearlever). Use `--integrate` / `--unintegrate` / `--diagnose` to manage the protocol handler.

### From Source
```bash
git clone https://github.com/patrickjaja/claude-desktop-bin.git
cd claude-desktop-bin
./scripts/build-local.sh --install
```

> **Note:** Source builds do not receive automatic updates. Pull and rebuild to update.

### ARM64 / aarch64 (Raspberry Pi 5, NVIDIA DGX Spark, Jetson, etc.)

ARM64 `.deb`, `.rpm`, AppImage, and Nix packages are available for **Raspberry Pi 5**, **NVIDIA DGX Spark** (Ubuntu 24.04 arm64), and **Jetson** (JetPack/Ubuntu 22.04 arm64). The APT and DNF repos serve both x86_64 and arm64 - your package manager picks the correct architecture automatically. Install exactly as above.

### Verifying the repository signing key

The APT and DNF repositories are GPG-signed. The install scripts import the key from GitHub Pages over HTTPS. To verify the key out-of-band, compare its fingerprint against the value published here (this README lives in the git repo, a separate channel from the Pages-hosted key):

```
Key:         Claude Desktop Linux <claude-desktop-linux@users.noreply.github.com>
Type:        RSA 4096
Fingerprint: 825A 7D15 D78B ABE4 5646  D5DF 3824 09F5 9790 8867
```

```bash
curl -fsSL https://patrickjaja.github.io/claude-desktop-bin/gpg-key.asc | gpg --show-keys --with-fingerprint
# The printed fingerprint must match the value above.
```

## Computer Use

**Our exclusive feature - not part of the official Linux beta.** Claude Desktop's built-in Computer Use MCP server exposes 27 tools for desktop automation (screenshot, click, type, scroll, drag, clipboard, and more). The **learn tools** (`learn_application`, `learn_screen_region`) generate interactive overlay tutorials that walk through any application's UI step by step.

Example prompt: *"Can you use computer use MCP to explain me the PhpStorm application?"*

**How it works on Linux:** upstream Computer Use is macOS-only - gated behind `process.platform==="darwin"`, macOS TCC permissions, and a native Swift executor. The patch ([fix_computer_use_linux.nim](patches/fix_computer_use_linux.nim)) removes the platform gates, routes both upstream executor factories to an injected Linux executor, bypasses TCC with a no-op `{granted: true}`, and auto-detects your session type to use the right tools (xdotool/ydotool, grim/spectacle/scrot/portal, plus `kwin-portal-bridge` on KDE Wayland). Install the packages for your session from [Computer Use dependencies](#computer-use-dependencies) below.

**Notes:**
- **Primary monitor only.** Screenshots, clicks, and the teach overlay target the primary display; use `switch_display` to target another for screenshots/clicks (teach overlay stays on primary).
- **App discovery** for the teach overlay scans `.desktop` files from `/usr/share/applications`, `~/.local/share/applications`, and Flatpak dirs, registering each with multiple name variants for flexible matching.
- **Teach overlay** stays interactive but blocks clicks to apps behind it during a tour (Electron's `setIgnoreMouseEvents` is [broken on X11](https://github.com/electron/electron/issues/16777)).

See [CLAUDE_BUILT_IN_MCP.md](baseline/CLAUDE_BUILT_IN_MCP.md#14-computer-use) for the full tool reference.

## Computer Use dependencies

Check your session type (`echo $XDG_SESSION_TYPE`) and desktop (`echo $XDG_CURRENT_DESKTOP`), then install the matching packages. At runtime the app auto-detects your compositor and calls the correct tools.

| Distro | X11 / XWayland | Wayland - Sway/Hyprland | Wayland - GNOME | Wayland - KDE Plasma |
|--------|----------------|-------------------------|-----------------|----------------------|
| **Arch** | `xdotool scrot imagemagick wmctrl` | `ydotool grim jq` (+`hyprland` on Hyprland) | `ydotool xdotool glib2 gnome-screenshot imagemagick python-gobject gst-plugin-pipewire` | *none - bundled bridge* |
| **Debian/Ubuntu** | `xdotool scrot imagemagick wmctrl` | `ydotool grim jq` (+`hyprland`) | `ydotool xdotool libglib2.0-bin gnome-screenshot imagemagick python3-gi gstreamer1.0-pipewire` | *none - bundled bridge* |
| **Fedora/RHEL** | `xdotool scrot ImageMagick wmctrl` | `ydotool grim jq` (+`hyprland`) | `ydotool xdotool glib2 gnome-screenshot ImageMagick python3-gobject pipewire-gstreamer` | *none - bundled bridge* |

> **KDE Plasma Wayland:** the bundled [`kwin-portal-bridge`](https://github.com/patrickjaja/kwin-portal-bridge) handles input, screenshots, clipboard, and display info natively via XDG portals - no extra packages. One consent prompt per session. Falls back to `ydotool` + `spectacle` if unavailable.
>
> **GNOME 46+** (Ubuntu 25.10+, Fedora 40+): screenshots use the XDG ScreenCast portal with PipeWire restore tokens - one permission dialog, then silent (needs `python-gobject`/`python3-gi` + `gst-plugin-pipewire`). Falls back to `gnome-screenshot` / `gdbus`. Set flat mouse accel for accurate clicks: `gsettings set org.gnome.desktop.peripherals.mouse accel-profile flat`.
>
> **Custom screenshot command:** set `COWORK_SCREENSHOT_CMD` to override auto-detection. Placeholders: `{FILE}`, `{X}`, `{Y}`, `{W}`, `{H}`. Example: `COWORK_SCREENSHOT_CMD='spectacle -b -n -r -o {FILE}'`

<a id="ydotool-setup-wayland"></a>
### ydotool setup (Wayland - GNOME, Sway, Hyprland)

Computer Use needs `ydotool` **v1.0+** and the `ydotoold` daemon for input on GNOME, Sway, and Hyprland Wayland. KDE Plasma does not need it.

**Arch / Fedora** ship v1.x in the repos:
```bash
sudo pacman -S ydotool && sudo systemctl enable --now ydotool   # Arch
sudo dnf install ydotool && sudo systemctl enable --now ydotool  # Fedora
```

**Ubuntu / Debian** still ship the **incompatible** v0.1.8 (Ubuntu 22.04/24.04/25.10) or nothing in main (Debian 13 trixie; v1.x is backports-only) - build v1.0.4 with the setup script:
```bash
curl -fsSL https://raw.githubusercontent.com/patrickjaja/claude-desktop-bin/master/scripts/setup-ydotool.sh | sudo bash
```

Restart Claude Desktop after setup.

> **Nix:** pass Computer Use deps via `claude-desktop.override { xdotool = pkgs.xdotool; scrot = pkgs.scrot; ydotool = pkgs.ydotool; grim = pkgs.grim; … }`. On NixOS the bundled `kwin-portal-bridge` won't run (glibc linker mismatch) - use the `ydotool`/`spectacle` fallback tools instead.

## Custom Themes

Recolor the whole app - chat, sidebar, Code/Cowork, dialogs, Quick Entry - by overriding CSS variables, injected into every window via Electron's `insertCSS()`. Each theme is **dual light/dark**: it ships a `light` and a `dark` palette, and the app's own toggle (Settings → Appearance) picks the matching one live. Every built-in is contrast-checked (WCAG AA).

**Quick start** - just pick a theme, no extra config needed:
```bash
echo '{"activeTheme": "mario"}' > ~/.config/Claude/claude-desktop-bin.json
# Restart Claude Desktop, then toggle Settings → Appearance for light/dark
```

The Mario theme ships a **light "overworld"** and a **dark "underground"** variant, with a bouncing mushroom loading spinner:

| Light (overworld) | Dark (underground) |
|-------------------|--------------------|
| ![Mario theme - light](themes/mario/2026-06-26_14-46-chat-light.png) | ![Mario theme - dark](themes/mario/2026-06-26_14-46-chat-dark.png) |

**Built-in themes** (each with a light + dark palette and a custom spinner):

| Theme | Light variant | Dark variant | Spinner |
|-------|---------------|--------------|---------|
| `mario` | sky-blue overworld | warm-brick underground | mushroom |
| `sweet` | blush/lavender | deep purple, vivid pink ([Sweet](https://github.com/EliverLara/Sweet)) | blossom |
| `nord` (alias `nordic`) | Snow Storm | Polar Night ([nordtheme.com](https://nordtheme.com)) | snowflake |
| `catppuccin-mocha` | Latte | Mocha ([catppuccin.com](https://catppuccin.com)) | cat |
| `catppuccin-macchiato` | Latte | Macchiato | cat |
| `catppuccin-frappe` | Latte | Frappe | cat |
| `catppuccin-latte` | Latte | Mocha | coffee cup |

Each theme can also inject raw `customCss` and replace the loading glyph with a custom SVG. See **[themes/README.md](themes/README.md)** for the schema, CSS-variable reference, contrast tips, and how to author your own.

## Multiple Profiles

Run several Claude Desktop instances side by side, each logged in to a different account, with fully isolated state for both Desktop and the Claude Code CLI it spawns. Useful for separating work from personal accounts, juggling SSO tenants, or testing config without touching your main install.

### Quick start

```bash
# One-time setup per profile
claude-desktop --create-profile=work
claude-desktop --create-profile=personal

# Launch (any of these work)
claude-desktop-work                     # via the per-profile shortcut
claude-desktop --profile=work           # via the system launcher
# …or click "Claude (work)" in your application menu

# Inspect / clean up
claude-desktop --list-profiles
claude-desktop --delete-profile=work    # removes entry points; user data preserved
```

The **default profile** (no `--profile=`, no named shortcut) is byte-identical to a single-instance install - same `~/.config/Claude`, same `~/.claude`, same sockets, same WM identity. You can run it alongside any number of named profiles.

A **named profile** (`--create-profile=NAME`, names match `[a-zA-Z0-9_-]+`, `default` reserved) installs three things in your home dir (no root needed): a per-profile Electron binary at `~/.local/lib/claude-desktop/claude-NAME`, a launcher symlink at `~/.local/bin/claude-desktop-NAME`, and an application-menu entry `Claude (NAME)`. User data is created lazily on first launch.

Three equivalent ways to select a profile at launch: `claude-desktop --profile=NAME`, `CLAUDE_PROFILE=NAME claude-desktop`, or the `claude-desktop-NAME` shortcut (infers the name from its basename). All export `CLAUDE_PROFILE`, which propagates through Electron and any spawned `claude` CLI.

### What's isolated

| Resource | Default profile | Named profile (e.g. `work`) |
|---|---|---|
| Electron userData (login, logs, settings, themes, Cowork sessions/Spaces, portal token) | `~/.config/Claude` | `~/.config/Claude-work` |
| Claude Code config (settings, projects, sessions, plugins) | `~/.claude` | `~/.claude-work` |
| Quick Entry toggle socket | `$XDG_RUNTIME_DIR/claude-desktop-qe.sock` | `…/claude-desktop-qe-work.sock` |
| systemd user scope (cgroup, portal identity) | `app-claude-PID.scope` | `app-claude-work-PID.scope` |
| WM_CLASS / Wayland app_id (taskbar grouping, Alt-Tab) | `claude` | `claude-work` |
| XDG autostart entry ("Start at login") | `~/.config/autostart/claude.desktop` | `…/claude-work.desktop` |

Plugins, MCP servers, login state, and chat history from one profile are **not** visible in another - profiles are independent installs, not shared views.

### Removing a profile

```bash
claude-desktop --delete-profile=work    # removes the three entry points
rm -rf ~/.config/Claude-work ~/.claude-work   # user data is preserved; delete manually for a clean slate
```

### SSO and URL routing

The `claude://` scheme is registered system-wide and points to the default profile's `.desktop` file. To route SSO callbacks to the profile that started them, claude-desktop-bin uses a marker mechanism ([`fix_profile_url_routing.nim`](patches/fix_profile_url_routing.nim)): when a profile calls `shell.openExternal()` on an auth URL it writes a timestamped marker at `$XDG_RUNTIME_DIR/claude-desktop-pending-auth-<profile>`; when the launcher receives a `claude://` callback with no explicit profile it picks the most recent marker (< 5 min old) and re-execs as that profile.

Sequential SSO into any number of profiles is reliable. Two edge cases misroute (the "most recent marker wins" rule): clicking an unrelated outbound link mid-flow, or two SSO flows in flight concurrently - just re-attempt. The marker is `0600` and holds only a timestamp. Escape hatch: `claude-desktop --profile=NAME 'claude://<callback-url>'`.

**Opening shared-artifact links:** a `claude://cowork/shared-artifact?uuid=…` link opens Claude Desktop when clicked as a real hyperlink. Pasting it into a browser address bar won't work (the omnibox treats unknown schemes as a search - a browser security gate). To open a copied link: `xdg-open 'claude://cowork/shared-artifact?uuid=…'`.

### Notes

- **Disk cost.** A named profile needs a real, independently-named binary (not a symlink) so Electron can derive a distinct WM_CLASS / Wayland `app_id` from `/proc/self/exe`. The launcher tries hardlink → reflink (btrfs/xfs CoW) → plain copy in order, so only cross-filesystem installs on a non-CoW disk actually pay the ~200 MB; sibling files (`libffmpeg.so`, `.pak`, `locales/`, …) are always shared symlinks. Package upgrades that leave the copy stale are re-materialised automatically on the next launch.
- **`--profile=NAME` without `--create-profile`** isolates state but not WM identity (window joins the default taskbar entry; suppress the hint with `CLAUDE_PROFILE_QUIET=1`).
- **[Quick Entry](#quick-entry) hotkey is not per-profile** - `--install-gnome-hotkey` targets the default profile; for a named one, bind `claude-desktop --profile=NAME --toggle` by hand.
- **NixOS** may not resolve Wayland portal identity (no `systemd-run --scope`); use `--install-gnome-hotkey`.

## Quick Entry

A global-hotkey popup (default `Ctrl+Alt+Space`) that opens a compact Claude prompt on the monitor where your cursor is. It works out of the box on **KDE Plasma**, **Hyprland**, and **Sway** via `xdg-desktop-portal` GlobalShortcuts.

Bind the toggle to any key with:
```bash
claude-desktop --toggle
```
This toggles Quick Entry in ~5-25 ms via a Unix domain socket, starting the app if it isn't running.

On **GNOME** the portal silently fails to register the hotkey - run once after install:
```bash
claude-desktop --install-gnome-hotkey                 # default Ctrl+Alt+Space
claude-desktop --install-gnome-hotkey '<Super>space'  # or any accelerator
```
This binds the key directly via `gsettings`, bypassing the portal. See [wayland.md](wayland.md#quick-entry-hotkey-not-firing-on-gnome). Run `claude-desktop --diagnose` to check hotkey status.

## Cowork setup (needs /dev/kvm)

Cowork (and Dispatch) run on the **official native Cowork VM backend** bundled inside the package (cowork-linux-helper + virtiofsd + smol-bin + QEMU/OVMF) - the same backend Anthropic ships in the official Linux build. There's no separate daemon to install; sessions run in a lightweight VM with `$HOME` shared in, which requires **`/dev/kvm`** on the host.

Install QEMU + UEFI firmware and grant `/dev/kvm` access (needed once):

```bash
# Arch:          sudo pacman -S --needed qemu-base edk2-ovmf
# Fedora/RHEL:   sudo dnf install qemu-system-x86 edk2-ovmf
# Debian/Ubuntu: sudo apt install qemu-system-x86 ovmf   # arm64: also qemu-efi-aarch64
sudo usermod -aG kvm "$USER"   # then log out and back in
```

If the workspace shows "Download failed" and clicking Download does nothing, it's almost always missing firmware (`edk2-ovmf`/`ovmf`) or missing `kvm` group membership. Cowork also needs the Claude Code CLI installed. **CoworkSpaces** are stored locally per account under `~/.config/Claude/local-agent-mode-sessions/` and are local-only on every platform (no claude.ai account-sync - upstream behavior by design).

> **Note — Cowork does not work inside a nested VM.** Because Cowork boots its own lightweight VM (the bundled backend downloads/builds a rootfs and starts it via QEMU/KVM), it needs real, stable access to `/dev/kvm`. Running Claude Desktop inside a hypervisor guest (VirtualBox, VMware, etc.) means Cowork would have to launch a VM *inside* a VM (nested virtualization), which most desktop hypervisors do not support reliably — VirtualBox in particular can hard-crash the entire guest when the nested VM starts. The app itself installs and runs fine in a VM; only the Cowork feature requires a bare-metal host (or a cloud instance with nested virtualization properly enabled).

## Third-Party / Enterprise Inference

**Run Claude Desktop entirely on your own inference backend - no personal claude.ai login required.** Point it at **Bedrock** (AWS), **Vertex AI** (Google Cloud), **Azure AI Foundry** (Microsoft), or any **Anthropic-compatible gateway** (LiteLLM, Portkey, in-house proxies) via a single `/etc/claude-desktop/managed-settings.json`. Chat, Code, and Cowork all work in 3P mode on Linux.

The official Linux build reads `/etc/claude-desktop/managed-settings.json` **natively** (top-level key `managedMcpServers`; also `inferenceProvider`, `deploymentMode`, `betaFeaturesEnabled`, …). Two Linux-only frontend patches remain ([`fix_ion_dist_linux.nim`](patches/fix_ion_dist_linux.nim)): a `mountPath` entry for the Linux org-plugins directory and a platform ternary fix.

> **Migrating from `enterprise.json`?** Rename the file - `sudo mv /etc/claude-desktop/enterprise.json /etc/claude-desktop/managed-settings.json` - the schema and keys are unchanged.

**Enable the tabs you want** by adding `"betaFeaturesEnabled": true`, `"chatTabEnabled": true`, `"coworkTabEnabled": true`, and `"isClaudeCodeForDesktopEnabled": true`. The in-app **Developer → Configure Third-Party Inference** window manages connection settings, credentials, model lists, sandbox restrictions, MCP servers, and org-plugin directories, and exports to `.mobileconfig` / `.reg` / plain JSON.

> **Switching back to personal (1P):** deployment mode is **sticky** - the first 3P launch persists `"deploymentMode": "3p"` to `~/.config/Claude-3p/claude_desktop_config.json`, so deleting `managed-settings.json` leaves the app stuck in 3P mode. Launch once with `claude-desktop --boot-1p-once`, or set that key to `"1p"`.

The official 3P docs cover only macOS and Windows. See **[docs/third-party-inference.md](docs/third-party-inference.md)** for a Linux-specific guide with a [5-minute LiteLLM quickstart](docs/third-party-inference.md#5-minute-local-quickstart-litellm-container), worked Vertex AI / gateway examples, and the [maximum `managed-settings.json`](docs/third-party-inference.md#maximum-managed-settingsjson-every-key). Key reference: [official configuration docs](https://claude.com/docs/cowork/3p/configuration) · [enterprise config](https://support.claude.com/en/articles/12622667-enterprise-configuration-for-claude-desktop) · [3P plugins/skills notes](https://support.claude.com/en/articles/14680753-extend-claude-cowork-with-third-party-platforms).

## Patches

The official Linux build is close to Linux-ready but not perfect. We apply a set of surgical JS patches to its `app.asar` at repackage time. The ones that actually change the bundle fall into two groups:

- **Value-adds** - features the official build doesn't provide on Linux (our reason to exist).
- **Linux fixes** - make upstream features that misbehave on Linux work correctly.

Each patch is a self-contained `patches/*.nim` file compiled to a native binary. Patterns use `[\w$]+` wildcards anchored on stable strings because upstream re-minifies between releases. The **debug pattern** column shows the `rg` command to locate the relevant code in a new version's `index.js`. When an update breaks a patch, only that file needs updating.

> A handful of the features listed here were later shipped natively by Anthropic. For those we keep a small set of **regression guards** in `patches/` (not listed below) that make no changes but fail the build loudly if the upstreamed Linux behavior ever disappears. `ls patches/*.nim` is the authoritative list of everything in the tree.

### Value-adds (Linux-only features)

| Patch | Purpose | Debug pattern |
|-------|---------|---------------|
| `add_feature_custom_themes.nim` | CSS theme injection - 7 dual light/dark themes + per-theme spinner reshape | Prepended IIFE, no regex |
| `fix_computer_use_linux.nim` | Enables Computer Use - removes platform gates, routes both executor factories to an injected Linux executor (portal+PipeWire/grim/GNOME D-Bus/spectacle/scrot, xdotool/ydotool) | `rg -o '.{0,60}executor not implemented' index.js` |
| `fix_computer_use_tcc.nim` | Stubs macOS TCC permission handlers to prevent error logs | Prepended IIFE, UUID extraction |
| `fix_buddy_ble_linux.nim` | Enables Hardware Buddy (Nibblet BLE) - forces feature flag, uses Web Bluetooth via BlueZ | `rg -o '2358734848.{0,50}' index.js` |
| `fix_quick_entry_position.nim` | Quick Entry opens on the cursor's monitor; position+focus retries gated to X11 (no Wayland jitter) | `rg -o 'getPrimaryDisplay.{0,50}' index.js` |
| `fix_quick_entry_cli_toggle.nim` | `claude-desktop --toggle` hotkey (~5-25 ms via Unix socket); per-profile socket path | `rg -o 'QUICK_ENTRY.{0,80}' index.js` |
| `fix_quick_entry_app_id.nim` | Distinct Wayland `app_id` for Quick Entry so shell-extension users can blacklist it ([#39](https://github.com/patrickjaja/claude-desktop-bin/issues/39)) | `rg -o '.{0,30}BrowserWindow.*titleBarStyle.*hidden.{0,30}' index.js` |
| `fix_quick_entry_ready_wayland.nim` | 100 ms timeout on Quick Entry ready-to-show wait (Wayland hang: `ready-to-show` never fires for frameless transparent windows) | `rg -o 'ready-to-show.{0,50}' index.js` |
| `fix_quick_entry_wayland_blur_guard.nim` | Guards Quick Entry blur-to-dismiss against spurious Wayland blur events | `rg -o '.{0,30}blur.{0,30}null.{0,30}' index.js` |
| `fix_profile_url_routing.nim` | Writes a per-profile auth-marker before opening SSO URLs so `claude://` callbacks route to the right profile | `rg -o 'shell\.openExternal' index.js` |
| `fix_profile_window_title.nim` | Appends profile name to window title (`Claude` → `Claude (work)`) | Prepended IIFE, `page-title-updated` listener |

### Linux fixes

| Patch | Purpose | Debug pattern |
|-------|---------|---------------|
| `enable_local_agent_mode.nim` | Forces Local Agent Mode / Code / plugin feature flags on and spoofs the client-OS platform header. Does **not** force-mark Cowork VM features - those reflect the native VM-capability probe | `rg -o 'status:"supported".{0,40}' index.js`; `rg -o 'anthropic-client-os-platform.{0,40}' index.js` |
| `fix_0_node_host.nim` | Fixes 4 sidecar runtime paths that join `process.resourcesPath+"app.asar"`; without this `fix_locale_paths` corrupts them (remote MCP fails, issue #140) | `rg -o 'process\.resourcesPath,"app.asar"' index.js` |
| `fix_app_quit.nim` | Uses `app.exit(0)` to prevent hang on exit | `rg -o '.{0,50}app\.quit.{0,50}' index.js` |
| `fix_asar_folder_drop.nim` | Prevents app.asar being misdetected as a folder drop on launch ([#24](https://github.com/patrickjaja/claude-desktop-bin/issues/24)) | `rg -o 'filter.*\.asar' index.js` |
| `fix_asar_workspace_cwd.nim` | Redirects app.asar workspace paths to home directory ([#24](https://github.com/patrickjaja/claude-desktop-bin/issues/24)) | `rg -o '__cdb_sanitizeCwd' index.js` |
| `fix_browse_files_linux.nim` | Enables `openDirectory` in the file dialog (upstream macOS-only) | `rg -o 'openDirectory.{0,60}' index.js` |
| `fix_browser_tools_linux.nim` | Enables Chrome browser tools - redirects native host to Claude Code's wrapper | `rg -o '"Helpers".{0,50}' index.js` |
| `fix_builtin_mcp_browser_env.nim` | Forwards DISPLAY/Wayland/XDG/DBUS/BROWSER env to built-in MCP servers so OAuth can open a browser ([#139](https://github.com/patrickjaja/claude-desktop-bin/issues/139)) | `rg -o '"HOME","LOGNAME","PATH","SHELL","TERM","USER".{0,40}' index.js` |
| `fix_cli_governor_memavailable.nim` | Computes CliGovernor memory pressure from `/proc/meminfo` `MemAvailable` instead of Electron's `free` - stops false pressure warnings ([#128](https://github.com/patrickjaja/claude-desktop-bin/issues/128)) | `rg -o 'getFreeMemoryRatio.{0,160}' index.js` |
| `fix_cowork_firmware_paths_linux.nim` | Adds Fedora/RHEL + Arch OVMF firmware paths (and Arch `/usr/lib/virtiofsd`) to the native Cowork VM capability probe - fixes "Download failed" on non-Debian distros | `rg -o 'OVMF_CODE.{0,80}' index.js` |
| `fix_cowork_font.nim` | Applies the user's chat font preference to the Cowork tab (avoids default Serif) | Prepended dom-ready IIFE, no regex |
| `fix_cross_device_rename.nim` | EXDEV fallback for cross-filesystem file moves | Uses `.rename(` literal |
| `fix_detected_projects_linux.nim` | Enables detected projects with Linux IDE paths (VSCode, Cursor, Zed) | `rg -o 'detectedProjects.{0,50}' index.js` |
| `fix_dispatch_linux.nim` | Enables Dispatch - forces bridge init, bypasses platform gate, forwards responses natively | `rg -o 'sessions-bridge.*init' index.js` |
| `fix_dock_bounce.nim` | Suppresses taskbar attention-stealing on KDE/Wayland | Prepended IIFE, no regex |
| `fix_imagine_linux.nim` | Enables Imagine/Visualize - forces GrowthBook flag for inline SVG/HTML rendering | `rg -o '3444158716' index.js` |
| `fix_ion_dist_linux.nim` | Adds Linux org-plugins mount path + platform ternary to the ion-dist 3P config SPA | `rg -o 'mountPath.{0,80}' ion-dist/assets/v1/*.js` |
| `fix_locale_paths.nim` | Redirects locale file paths to the Linux install location | Global string replace on `process.resourcesPath` |
| `fix_marketplace_linux.nim` | Forces host-local mode for plugin operations; promotes `$HOME`-scoped CLI plugins to user scope ("Personal Plugins") | `rg -o 'function \w+\(\w+\)\{return\(\w+==null.*mode.*ccd' index.js` |
| `fix_native_frame.nim` | Default: Windows-style integrated titlebar on Linux. Opt-out via `CLAUDE_NATIVE_TITLEBAR=1` / `--native-titlebar` for the native GTK frame | `rg -o 'titleBarStyle:process\.platform.{0,80}' index.js` |
| `fix_open_in_editor_linux.nim` | Makes "Open in VS Code / Cursor / Zed / Windsurf" work in Local Code Sessions via an `xdg`-based shim | `rg -o 'getApplicationInfoForProtocol.{0,40}' index.js` |
| `fix_process_argv_renderer.nim` | Injects `process.argv=[]` in renderer preload to prevent TypeError | `rg -o '.{0,30}\.argv.{0,30}' mainView.js` |
| `fix_renderer_gone_suppressed_log.nim` | Logs main-webview renderer deaths upstream silently swallows (OOM SIGKILL left no trace) ([#128](https://github.com/patrickjaja/claude-desktop-bin/issues/128)) | `rg -o 'render process gone \(suppressed\).{0,60}' index.js` |
| `fix_sensitive_dirs_linux.nim` | Adds Linux entries (`.local/share/keyrings`, `.pki`, `.config/autostart`) to the sandbox sensitive-directories block list | `rg -o '\.gnupg.{0,80}' index.js` |
| `fix_tray_dbus.nim` | Prevents DBus race conditions with mutex and cleanup delay | `rg -o 'menuBarEnabled.*function' index.js` |
| `fix_tray_icon_theme.nim` | Theme-aware tray icon (light/dark) | `rg -o 'nativeTheme.{0,50}tray' index.js` |
| `fix_updater_state_linux.nim` | Adds version fields to idle updater state to prevent TypeError | `rg -o 'status:"idle".{0,50}' index.js` |
| `fix_utility_process_kill.nim` | SIGKILL fallback when UtilityProcess doesn't exit gracefully | `rg -o 'Killing utiltiy proccess' index.js` |
| `fix_window_bounds.nim` | Fixes BrowserView bounds on maximize/snap, Quick Entry blur | Injected IIFE, minimal regex |
| `fix_claude_code.nim` | Detects the system-installed `claude` binary and wires it into Code status | `rg -o 'async getStatus\(\)\{.{0,200}' index.js` |
| `fix_startup_settings.nim` | Per-profile "Start at login" XDG autostart handling for named profiles (the base toggle is upstreamed) | `rg -o 'isStartupOnLoginEnabled.{0,50}' index.js` |

## Command-line flags

Flags this project adds on top of the official build (run `claude-desktop --help` for the full list). All are optional; without any, `claude-desktop` just launches the default profile.

| Flag | Description |
|------|-------------|
| `--profile=NAME` | Launch (or target a subcommand at) a named [profile](#multiple-profiles). Also selectable via a `claude-desktop-NAME` shortcut or `CLAUDE_PROFILE=NAME` |
| `--create-profile=NAME` | Create a [profile](#multiple-profiles) (user-local binary, launcher, and menu entry; own login/logs/config) |
| `--delete-profile=NAME` | Remove a profile's entry points (user data preserved) |
| `--list-profiles` | List installed profiles |
| `--toggle` | Toggle the [Quick Entry](#quick-entry) overlay (bind to a global shortcut) |
| `--install-gnome-hotkey [ACCEL]` | Bind the Quick Entry hotkey on GNOME, where the portal doesn't (default `Ctrl+Alt+Space`); `--uninstall-gnome-hotkey` removes it |
| `--native-titlebar` | Use the native window frame instead of the integrated titlebar (same as `CLAUDE_NATIVE_TITLEBAR=1`) |
| `--no-systemd-scope` | Skip the `systemd --user --scope` wrapper for this launch (same as `CLAUDE_DISABLE_SYSTEMD_SCOPE=1`) |
| `--diagnose` | Print session type, portal status, and hotkey state for issue reports |
| `--integrate` / `--unintegrate` | Register / remove the `claude://` handler and menu entry (AppImage only; happens automatically on launch) |

## Environment Variables

| Variable | Values | Description |
|----------|--------|-------------|
| `CLAUDE_PROFILE` | name | Select a profile by name. Inherited by Electron and Claude Code so per-profile sockets and config dirs are picked up everywhere |
| `CLAUDE_PROFILE_QUIET` | `1` | Suppress the "no per-profile WM identity" hint when `CLAUDE_PROFILE` is set without a matching `--create-profile` |
| `CLAUDE_CONFIG_DIR` | path | Override Claude Code's config dir. Auto-set by the launcher when `CLAUDE_PROFILE` is active |
| `CLAUDE_DISABLE_GPU` | `1`, `full` | Fix white screen on some GPU/driver combos ([#13](https://github.com/patrickjaja/claude-desktop-bin/issues/13)). `1` disables compositing only, `full` disables GPU entirely |
| `CLAUDE_USE_XWAYLAND` | `1` | Force XWayland instead of native Wayland |
| `CLAUDE_ENABLE_VULKAN` | `1` | Keep Vulkan enabled on native Wayland. Default off: Chromium (Electron 42) refuses to pair Vulkan with `--ozone-platform=wayland`, causing a silent no-window startup. Only affects Wayland |
| `CLAUDE_MENU_BAR` | `auto`, `visible`, `hidden` | Menu bar visibility (default: `auto`, toggle with Alt) |
| `CLAUDE_DEV_TOOLS` | `detach` | Open Chromium DevTools on launch |
| `CLAUDE_ELECTRON` | path | Override Electron binary path |
| `CLAUDE_APP_ASAR` | path | Override app.asar path |
| `CLAUDE_NATIVE_TITLEBAR` | `1` | Restore the native window frame (default: integrated titlebar). Equivalent to `--native-titlebar`. See [#100](https://github.com/patrickjaja/claude-desktop-bin/pull/100) |
| `CLAUDE_DISABLE_SYSTEMD_SCOPE` | `1` | Skip the `systemd-run --user --scope` wrapper. Use in sandboxes (bwrap, distrobox) where the systemd private socket is unreachable. Equivalent to `--no-systemd-scope`. See [#89](https://github.com/patrickjaja/claude-desktop-bin/issues/89) |
| `ELECTRON_ENABLE_LOGGING` | `1` | Log Electron main process to stderr |

Set permanently in `~/.bashrc` / `~/.zshrc`, or pass per-launch: `CLAUDE_DISABLE_GPU=1 claude-desktop`

## Debugging

Runtime logs are in `~/.config/Claude/logs/` (`main.log`, `claude.ai-web.log`, `mcp.log`). With a 3P `managed-settings.json` present, logs are under `~/.config/Claude-3p/`; named profiles use `~/.config/Claude-<profile>/`.

```bash
# Tail logs in real-time
tail -f ~/.config/Claude/logs/main.log

# Search for errors across all logs
grep -ri 'error\|exception\|fatal' ~/.config/Claude/logs/

# Launch with DevTools + full logging
CLAUDE_DEV_TOOLS=detach ELECTRON_ENABLE_LOGGING=1 claude-desktop 2>&1 | tee /tmp/claude-debug.log
```

**Clear stale Cowork sessions** (stuck "setting up workspace", or the model replaying old errors):
```bash
rm -rf ~/.config/Claude/local-agent-mode-sessions/
```

Computer Use patches emit `[claude-cu] diagnostics:` lines at startup showing the detected session, available/missing tools, and screenshot cascade - run `claude-desktop` from a terminal and share that output when reporting Computer Use issues.

## Known Limitations

- **App identity on Wayland.** `xdg-desktop-portal` resolves unsandboxed apps via the systemd user scope. We launch under `app-claude-*.scope` and install the `.desktop` as `claude.desktop`; the id `claude` matches Chromium's autogenerated scope, so WM_CLASS, Wayland `app_id`, and the `.desktop` basename all agree. KDE global shortcuts and persistent portal authorizations attach to that id and survive across sessions.
  - If you had `com.anthropic.claude-desktop.desktop` pinned from an earlier release, **re-pin once**.
  - Custom X11/Wayland WM rules matching `Claude` or `com.anthropic.claude-desktop` need updating to `claude` (named profiles add a `-<profile>` suffix).
  - GNOME shell-extension blacklists (Rounded Window Corners, Unite, Blur My Shell) referencing `com.anthropic.claude-quick-entry` should become `claude-quick-entry`.
  - **NixOS** doesn't use `systemd-run --scope`; portal identity may not resolve on GNOME Wayland - use `--install-gnome-hotkey`.
  - **Sandboxes/containers** without a reachable user-systemd (bwrap, distrobox, restricted Flatpaks) auto-skip the scope wrap; force it with `--no-systemd-scope` / `CLAUDE_DISABLE_SYSTEMD_SCOPE=1` if the socket exists but is unreachable ([#89](https://github.com/patrickjaja/claude-desktop-bin/issues/89)).
- **Computer Use is primary-monitor only** - see [Computer Use](#computer-use).
- **CoworkSpaces are local-only** on every platform (no account-sync) - a set created on macOS/Windows won't transfer to Linux. Upstream behavior.

## Automation

CI polls the official apt Packages index daily, downloads the latest official `.deb` (verifying GPG + SHA256), extracts and patches its `app.asar`, and **validates every patch in Docker** (`makepkg` in `archlinux:base-devel`) before publishing. Each patch exits 1 if its pattern doesn't match, so a broken package never reaches users - the pipeline stops with a clear `[FAIL]` and the AUR/repo packages stay on the last-good version until patches are updated.

## Repository Structure

- `.github/workflows/` - GitHub Actions automation (ingest, patch, validate, publish)
- `scripts/` - build, validation, and launcher scripts
- `patches/` - Nim patch sources + Makefile (compiled to native binaries)
- `js/` - shared JS snippets embedded by the patches
- `packaging/` - Debian, RPM, AppImage, and Nix build scripts
- `baseline/` - version-sensitive reference docs re-validated each release
- `PKGBUILD.template` - AUR package template

## See Also

- [tweakcc](https://github.com/Piebald-AI/tweakcc) - a CLI tool for customizing Claude Code (system prompts, themes, UI). Same patching-JS-to-make-it-yours energy. Thanks to the Piebald team.

## Legal Notice

> This is an **unofficial community project** for educational and research purposes.
> Claude Desktop is proprietary software owned by **Anthropic PBC**.
>
> This repository contains only build scripts and patches - not the Claude Desktop
> application itself. The upstream binary is downloaded directly from Anthropic
> during the build process.
>
> This project is not affiliated with, endorsed by, or sponsored by Anthropic.
> "Claude" is a trademark of Anthropic PBC.

---

<p align="center"><sub>Built with ❤️ for the Linux community</sub></p>
