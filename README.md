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

- [**Computer Use**](#computer-use) - desktop automation (screenshot, click, type, scroll, teach mode).
- [**Custom Themes**](#custom-themes) - 7 built-in dual light/dark themes with custom loading spinners, or roll your own.
- [**Multiple Profiles**](#multiple-profiles) - run several instances side by side, each logged in to a different account with fully isolated state.
- [**Quick Entry**](#quick-entry) - global hotkey popup (Ctrl+Alt+Space), multi-monitor and Wayland-aware.

Everything else - Chat, Cowork, Claude Code, Browser Tools, 3P/enterprise inference - is the **official upstream build**, preserved through the repackage. Where its shared cross-platform bundle still gates a feature to macOS/Windows or misbehaves on a Linux desktop, we ship a **Linux fix** (see [Patches](#patches) - each entry states exactly why it exists).

> **If you run Ubuntu 22.04+ / Debian 12+,** Anthropic's [official `.deb`](https://code.claude.com/docs/en/desktop-linux) installs the base app directly. Use this project if you're on Arch/Fedora/RHEL/Nix/AppImage, or if you want the four value-adds and Linux fixes above.

<details>
<summary><b>Table of contents</b></summary>

- [Installation](#installation)
- [Computer Use](#computer-use)
- [Custom Themes](#custom-themes)
- [Multiple Profiles](#multiple-profiles)
- [Quick Entry](#quick-entry)
- [Cowork setup (needs /dev/kvm)](#cowork-setup-needs-devkvm)
- [Third-Party / Enterprise Inference](#third-party--enterprise-inference)
- [Patches](#patches)
- [Command-line flags](#command-line-flags)
- [Environment Variables](#environment-variables)
- [Feature Flag Overrides (advanced)](#feature-flag-overrides-advanced)
- [Debugging](#debugging)
- [Known Limitations](#known-limitations)
- [Automation](#automation)
- [Repository Structure](#repository-structure)
- [See Also](#see-also)
- [Legal Notice](#legal-notice)

</details>

## Installation

> **Upgrading from an older release? (temporary note)** Cowork is now bundled directly in the app (Anthropic ships it in the official `.deb` we repackage), so the separate `claude-cowork-service` daemon has been **deprecated and fully removed** - you can uninstall it. In exchange, Cowork now needs a QEMU/KVM setup on the host (this is a breaking change). Even if you've been a user for a while, please walk through your distro's section below step by step and install the **Cowork** optional dependencies + join the `kvm` group. See [Cowork setup](#cowork-setup-needs-devkvm) for details.

Pick your distro below. [Computer Use](#computer-use) works out of the box everywhere - all backends are bundled, nothing to install. The only optional dependency to care about is **Cowork** (agent workspace VM), listed per distro.

### Arch Linux / Manjaro (AUR)
```bash
yay -S claude-desktop-bin
```
Updates arrive through your AUR helper (e.g. `yay -Syu`).

**Optional deps.**

**Cowork** (agent workspace VM). Not auto-installed (pacman skips `optdepends`); run the line for your arch:

```bash
sudo pacman -S --needed qemu-system-x86 edk2-ovmf virtiofsd     # x86_64
sudo pacman -S --needed qemu-system-aarch64 edk2-aarch64 virtiofsd  # aarch64
# then join the kvm group (once, needs re-login): sudo usermod -aG kvm "$USER"
```

> **Arch Linux ARM / EndeavourOS ARM / Manjaro ARM (native aarch64 host, e.g. Raspberry Pi 5):** `edk2-aarch64` is `arch=any` on archlinux.org but Arch Linux ARM's repos don't carry it, so `pacman -S edk2-aarch64` fails with `target not found` even after `-Syu` ([ALARM forum #16140](https://archlinuxarm.org/forum/viewtopic.php?t=16140)). Since the package is architecture-independent, grab it from the x86_64 Arch mirrors and install locally: `curl -L https://archlinux.org/packages/extra/any/edk2-aarch64/download -o edk2-aarch64.pkg.tar.zst && sudo pacman -U ./edk2-aarch64.pkg.tar.zst`.

Also optional: `nodejs` (system MCP servers), `sqlite` (project detection), `claude-code`.

### Debian / Ubuntu (APT Repository)

> **Requires Ubuntu 22.04+ / Debian 12+** (glibc 2.34 or newer). Debian 11 (bullseye) is no longer supported.

```bash
# Add repository (one-time setup)
curl -fsSL https://patrickjaja.github.io/claude-desktop-bin/install.sh | sudo bash

# Install
sudo apt install claude-desktop-bin
```
Updates are automatic via `sudo apt update && sudo apt upgrade`.

**Optional deps.**

**Cowork** (agent workspace VM). Auto-installed by `apt` (`Recommends`, mirroring Anthropic's official `.deb`); run manually only if you skipped recommends:

```bash
sudo apt install qemu-system-x86 ovmf virtiofsd        # arm64: qemu-system-arm qemu-efi-aarch64 virtiofsd
# then join the kvm group (once, needs re-login): sudo usermod -aG kvm "$USER"
```

<details>
<summary>Manual .deb install (without APT repo)</summary>

```bash
wget https://github.com/patrickjaja/claude-desktop-bin/releases/latest/download/claude-desktop-bin_1.20186.1-1_amd64.deb
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

**Optional deps.**

**Cowork** (agent workspace VM). Auto-installed by `dnf` (weak deps); run manually only if you disabled them:

```bash
sudo dnf install qemu-system-x86 edk2-ovmf virtiofsd   # arm64: qemu-system-aarch64 edk2-aarch64 · RHEL: qemu-kvm instead of qemu-system-x86
# then join the kvm group (once, needs re-login): sudo usermod -aG kvm "$USER"
```

<details>
<summary>Manual .rpm install (without DNF repo)</summary>

```bash
wget https://github.com/patrickjaja/claude-desktop-bin/releases/latest/download/claude-desktop-bin-1.20186.1-1.x86_64.rpm
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

> **Optional deps on Nix: wired automatically.** The flake pulls the Cowork tools (`qemu`, `virtiofsd`, OVMF firmware) from nixpkgs and bakes them into the app's closure - nothing to install. Use `.override { … }` to swap or drop a tool (e.g. `qemu = null;` shrinks the closure if you don't need Cowork). Only one host-level step remains, in NixOS form:
>
> ```nix
> users.users.<you>.extraGroups = [ "kvm" ];  # Cowork: /dev/kvm access (once, needs re-login)
> ```
>
> **NixOS Computer Use caveat:** the static bridges (X11 / XWayland / Sway / Hyprland / Niri) run as-is; the glibc-dynamic GNOME/KDE bridges do not - see [Computer Use dependencies](docs/computer-use-dependencies.md#nixos) for the `.override` workaround. If your flake pins a release older than v1.18286.0, virtiofsd and OVMF need manual exposure - see the notes in [`packaging/nix/package.nix`](packaging/nix/package.nix).

### AppImage (Any Distro)

Works on standard and **immutable/atomic distros** - Bazzite, Fedora Silverblue/Kinoite, SteamOS, Universal Blue, NixOS (without the Nix package), and any other glibc-based Linux.

The `claude://` protocol handler (needed for OAuth sign-in) is **automatically registered** on first launch. If you move or rename the AppImage, the registration updates on the next launch.

```bash
# Download from GitHub Releases
wget https://github.com/patrickjaja/claude-desktop-bin/releases/latest/download/Claude_Desktop-1.20186.1-x86_64.AppImage
chmod +x Claude_Desktop-*-x86_64.AppImage
./Claude_Desktop-*-x86_64.AppImage
```

> **Update:** AppImage supports delta updates via [appimagetool](https://github.com/AppImageCommunity/AppImageUpdate) - only changed blocks are downloaded (`appimageupdatetool Claude_Desktop-*.AppImage`, or `--appimage-update` from within). Compatible with [AppImageLauncher](https://github.com/TheAssassin/AppImageLauncher) and [Gear Lever](https://github.com/mijorus/gearlever). Use `--integrate` / `--unintegrate` / `--diagnose` to manage the protocol handler.
>
> **Optional deps.** For **Cowork** (VM), install from your host's repos: Arch/Fedora `qemu-system-x86 edk2-ovmf virtiofsd` · Debian/Ubuntu `qemu-system-x86 ovmf virtiofsd` (arm64 firmware differs - see [Cowork setup](#cowork-setup-needs-devkvm)).

### From Source
```bash
git clone https://github.com/patrickjaja/claude-desktop-bin.git
cd claude-desktop-bin
./scripts/build-local.sh --install
```

> **Note:** Source builds do not receive automatic updates. Pull and rebuild to update.
>
> **Optional deps.** A source build installs the native package for your distro, so the optional deps are the same as that distro's section above (e.g. on Arch, install the Cowork packages by hand since pacman doesn't pull `optdepends`).

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

**Our exclusive feature - not part of the official Linux build.** Claude Desktop's built-in Computer Use MCP server exposes 27 tools for desktop automation (screenshot, click, type, scroll, drag, clipboard, and more), plus **learn tools** that generate interactive overlay tutorials for any app. Upstream gates it to macOS/Windows and ships no Linux backend; the patch ([`fix_computer_use_linux.nim`](patches/fix_computer_use_linux.nim)) removes the platform gates and injects a Linux executor that auto-detects your session and routes to a bundled first-party bridge: [`x11-bridge`](https://github.com/patrickjaja/x11-bridge) on X11 / XWayland, [`wlroots-bridge`](https://github.com/patrickjaja/wlroots-bridge) on Sway / Hyprland / Niri (native virtual-pointer/keyboard + screencopy + foreign-toplevel protocols), [`gnome-portal-bridge`](https://github.com/patrickjaja/gnome-bridge) on GNOME Wayland (XDG RemoteDesktop + ScreenCast portal, one consent dialog per session, persisted on GNOME 46+; needs PipeWire >= 1.0.5, i.e. Ubuntu 24.04+ / Fedora 40+ / Debian 13+), and [`kwin-portal-bridge`](https://github.com/patrickjaja/kwin-portal-bridge) on KDE Plasma 6.6+. No third-party input/screenshot tools needed; only exotic Wayland compositors fall back to `ydotool`.

**Nothing to install** - the bridges ship inside the package. See **[docs/computer-use.md](docs/computer-use.md)** for how it works, the notes (primary-monitor, app discovery, teach overlay), and links to the [tool reference](baseline/CLAUDE_BUILT_IN_MCP.md#14-computer-use); [Computer Use dependencies](docs/computer-use-dependencies.md) has the per-session matrix and the exotic-compositor `ydotool` fallback.

## Custom Themes

Recolor the whole app - chat, sidebar, Code/Cowork, dialogs, Quick Entry - by overriding CSS variables, injected into every window via Electron's `insertCSS()`. Each theme is **dual light/dark**: it ships a `light` and a `dark` palette, and the app's own toggle (Settings → Appearance) picks the matching one live. Every built-in is contrast-checked (WCAG AA).

**Quick start** - just pick a theme, no extra config needed:
```bash
echo '{"activeTheme": "mario"}' > ~/.config/Claude/claude-desktop-bin.jsonc
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

**QEMU + OVMF firmware + virtiofsd are recommended dependencies** of the `.deb` / `.rpm` / AUR packages (matching Anthropic's official `.deb`), so a normal `apt`/`dnf` install pulls them by default. One step remains (needed once):

```bash
sudo usermod -aG kvm "$USER"        # /dev/kvm access - then log out and back in
```

The Claude Code CLI that Cowork/Dispatch drive is managed by the app itself - nothing to install. To pin your own binary, set `CLAUDE_CODE_LOCAL_BINARY=/path/to/claude`.

> **AppImage, Nix, or source builds** don't pull system packages - install QEMU + UEFI firmware + virtiofsd yourself first (firmware package name differs on arm64):
> ```bash
> # Arch:          sudo pacman -S --needed qemu-base edk2-ovmf virtiofsd   # arm64: edk2-aarch64 instead of edk2-ovmf
> # Fedora/RHEL:   sudo dnf install qemu-system-x86 edk2-ovmf virtiofsd    # arm64: qemu-system-aarch64 edk2-aarch64
> # Debian/Ubuntu: sudo apt install qemu-system-x86 ovmf virtiofsd         # Ubuntu 22.04: no virtiofsd pkg needed (bundled copy is used)
> #                                                                        # arm64: qemu-system-arm qemu-efi-aarch64
> ```
> A **system virtiofsd is required on everything except Ubuntu 22.x** - the app's capability probe only falls back to the bundled `virtiofsd` on jammy (`/etc/os-release` gate). Without it Cowork reports "Cowork requires QEMU …" even when qemu and firmware are present (issue #177). If your distro installs virtiofsd outside the probed paths (`/usr/libexec`, `/usr/lib`, `/usr/lib/qemu`, `/usr/bin`), point the app at it with `CLAUDE_VIRTIOFSD_PATH=/path/to/virtiofsd`; a custom firmware location can likewise be set with `CLAUDE_OVMF_CODE_PATH=/path/to/OVMF_CODE.fd` (its `*_VARS.fd` sibling must sit next to it). The Nix flake wires all three automatically (see the Nix install section).
> On Arch Linux ARM / EndeavourOS ARM / Manjaro ARM (native aarch64 hosts), `edk2-aarch64` is missing from the ALARM repos even though it's `arch=any` upstream - see the Arch install section above for the manual-download workaround.

### Troubleshooting Cowork

Run **`claude-desktop --diagnose`** first - it prints a full capability probe (KVM, vhost_vsock, QEMU, firmware, virtiofsd) and tells you exactly which piece is missing. Common popups and their fixes:

- **"Download failed" / clicking Download does nothing** - almost always missing `kvm` group membership (`sudo usermod -aG kvm "$USER"`, then re-login), or on AppImage/Nix missing firmware or system virtiofsd.
- **"Virtualization isn't fully set up" / "Cowork requires QEMU. Install it with …"** - QEMU, OVMF firmware, or virtiofsd is missing. The popup's `apt` command is upstream's and only correct on Debian/Ubuntu - use your distro's equivalent instead: `sudo pacman -S --needed qemu-system-x86 edk2-ovmf virtiofsd` (Arch), `sudo dnf install qemu-system-x86 edk2-ovmf virtiofsd` (Fedora; on RHEL use `qemu-kvm` instead of `qemu-system-x86`); aarch64 swaps in `qemu-system-aarch64` + `edk2-aarch64`. Details in your distro's [install section](#installation) (or the [AppImage/Nix note above](#cowork-setup-needs-devkvm)).
- **"Cowork requires the vhost_vsock kernel module"** - on systemd distros this normally never appears: systemd pre-creates `/dev/vhost-vsock` at boot (static device node) and the kernel auto-loads the module the moment QEMU opens it. If you do see it, you are on a non-systemd init (Artix, Void), inside a container, or on a kernel built without the module - load it with `sudo modprobe vhost_vsock` and persist it (`echo vhost_vsock | sudo tee /etc/modules-load.d/vhost_vsock.conf`, or your init's equivalent).
- **Dispatch stops responding or behaves oddly** - the Dispatch conversation keeps its state (including past errors) across restarts, so a broken session stays broken. Reset it: open the **⋮** menu next to the Dispatch title and click **Delete conversation**, then send your request again in the fresh conversation.

  ![Reset Dispatch: ⋮ menu, then Delete conversation](docs/dispatch/reset-dispatch-conversation.png)

No symlinks or manual path configuration are needed: the capability probe searches the distro-native firmware and virtiofsd locations (`/usr/share/edk2/x64/OVMF_CODE.4m.fd`, `/usr/lib/virtiofsd`, …) out of the box. Custom locations can be set via `CLAUDE_OVMF_CODE_PATH` / `CLAUDE_VIRTIOFSD_PATH` (see above).

**CoworkSpaces** are stored locally per account under `~/.config/Claude/local-agent-mode-sessions/` (see [Known Limitations](#known-limitations)).

> **Note — Cowork does not work inside a nested VM.** Because Cowork boots its own lightweight VM (the bundled backend downloads/builds a rootfs and starts it via QEMU/KVM), it needs real, stable access to `/dev/kvm`. Running Claude Desktop inside a hypervisor guest (VirtualBox, VMware, etc.) means Cowork would have to launch a VM *inside* a VM (nested virtualization), which most desktop hypervisors do not support reliably — VirtualBox in particular can hard-crash the entire guest when the nested VM starts. The app itself installs and runs fine in a VM; only the Cowork feature requires a bare-metal host (or a cloud instance with nested virtualization properly enabled).

## Third-Party / Enterprise Inference

**Run Claude Desktop entirely on your own inference backend - no personal claude.ai login required.** Point it at **Bedrock** (AWS), **Vertex AI** (Google Cloud), **Azure AI Foundry** (Microsoft), or any **Anthropic-compatible gateway** (LiteLLM, Portkey, in-house proxies) via a single `/etc/claude-desktop/managed-settings.json`, which the official Linux build reads natively. Chat, Code, and Cowork all work in 3P mode on Linux.

The official 3P docs cover only macOS and Windows. **[docs/third-party-inference.md](docs/third-party-inference.md)** is the Linux guide: a [5-minute LiteLLM quickstart](docs/third-party-inference.md#5-minute-local-quickstart-litellm-container), worked Vertex AI / gateway / Bedrock examples, the [maximum `managed-settings.json`](docs/third-party-inference.md#maximum-managed-settingsjson-every-key), the [`enterprise.json` → `managed-settings.json` migration](docs/third-party-inference.md), and [switching back to personal (1P)](docs/third-party-inference.md#common-gotchas).

## Patches

The official Linux build ships one cross-platform JS bundle: plenty of code paths in it check `process.platform` and only serve `darwin`/`win32`, and some upstream behavior misfires in a Linux desktop environment. We apply a set of surgical JS patches to the `app.asar` at repackage time. They fall into three groups:

- **[Value-adds](#value-adds-linux-only-features)** - features that don't exist upstream, or that we back with our own Linux implementations.
- **[Linux fixes](#linux-fixes)** - upstream features that are still gated to macOS/Windows in the shared bundle, or that break in a Linux environment.
- **[Regression guards](#regression-guards)** - change nothing; they assert native Linux behavior the app relies on is still present and fail the build loudly if it ever disappears.

Every package ships the official build's install tree byte-identical except for the patched `app.asar` (plus our bundled Computer Use bridges in `resources/`), so runtime path resolution (`process.resourcesPath`, `app.isPackaged`) behaves exactly as on the stock Anthropic `.deb`.

Each patch is a self-contained `patches/*.nim` file compiled to a native binary. Patterns use `[\w$]+` wildcards anchored on stable strings because upstream re-minifies between releases; every sub-patch must match or the build fails, so a broken assumption surfaces at build time, never at runtime. When an update breaks a patch, only that file needs updating - each patch source documents the anchor strings it matches on.

> **We keep this set as small as possible.** On each upstream release every patch is re-audited against a fresh unpatched bundle - a patch that still applies cleanly isn't proof it's still needed, so each must be confirmed to genuinely do work (or the feature live-tested) to stay. When Anthropic ships a behavior natively, the patch is removed or converted to a regression guard. `ls patches/*.nim` is the authoritative list of everything in the tree.

### Value-adds (Linux-only features)

Features the official build doesn't have - either they exist nowhere upstream (themes, profiles, flag overrides) or upstream ships them without any Linux backend and we provide one (Computer Use, Quick Entry ergonomics, Buddy).

| Patch | What it does & why it exists |
|-------|------------------------------|
| `add_feature_custom_themes.nim` | CSS theme injection - 7 dual light/dark themes + per-theme loading spinner, applied to every window via `insertCSS()`. Upstream has no theming layer beyond the light/dark toggle |
| `add_growthbook_overrides.nim` | [Local feature-flag overrides](#feature-flag-overrides-advanced) via `claude-desktop-bin.jsonc` - hooks the GrowthBook features-store setter so user overrides win over the server rollout. Upstream has no local override mechanism (the flag cache is encrypted) |
| `fix_computer_use_linux.nim` | Enables Computer Use. Upstream gates it to macOS/Windows (platform set, executor factories, enable gate) and ships zero Linux input/screenshot backends. Removes the gates and injects a Linux executor backed by the four bundled first-party bridges (x11-bridge on X11/XWayland, wlroots-bridge on Sway/Hyprland/Niri, gnome-portal-bridge on GNOME Wayland, kwin-portal-bridge on KDE Wayland; ydotool only on exotic compositors) |
| `fix_computer_use_tcc.nim` | Stubs the macOS TCC permission IPC (accessibility / screen recording) with `not_applicable` answers - TCC has no Linux equivalent, and without handlers the renderer's permission checks throw "No handler registered" |
| `fix_buddy_ble_linux.nim` | Enables Hardware Buddy (Nibblet BLE). Linux is outside the upstream rollout, so the flag is forced on Linux (the in-app toggle still wins); also pre-registers the BLE IPC handlers to avoid a startup race. Bluetooth works via Web Bluetooth on BlueZ |
| `fix_quick_entry_position.nim` | [Quick Entry](#quick-entry) opens on the cursor's monitor instead of the primary display and auto-focuses the input; position/focus retries run only on X11 (Wayland doesn't reposition after `show()`) |
| `fix_quick_entry_cli_toggle.nim` | `claude-desktop --toggle`: toggles Quick Entry in ~5-25 ms via a Unix socket (per-profile path) instead of a ~300 ms Electron spawn - fast enough for a global hotkey |
| `fix_quick_entry_app_id.nim` | Gives Quick Entry its own Wayland `app_id` (`claude-quick-entry`) so shell-extension rules can target it separately from the main window ([#39](https://github.com/patrickjaja/claude-desktop-bin/issues/39)) |
| `fix_quick_entry_ready_wayland.nim` | On native Wayland `ready-to-show` never fires for frameless transparent windows, hanging the popup - adds a 100 ms timeout |
| `fix_quick_entry_wayland_blur_guard.nim` | Wayland emits spurious blur events that dismissed Quick Entry immediately; blur-to-dismiss now only counts after the window was actually focused |
| `fix_profile_url_routing.nim` | [Multi-profile](#multiple-profiles) SSO: writes a per-profile auth marker before opening SSO URLs so the launcher can route the `claude://` callback to the profile that started the flow |
| `fix_profile_window_title.nim` | Appends the profile name to the window title (`Claude` → `Claude (work)`) so profiles are distinguishable in Alt-Tab/taskbar |

### Linux fixes

Upstream ships the same JS bundle to all platforms; these patches open `darwin`/`win32`-only gates for Linux, or fix behavior that breaks in a Linux desktop environment. Each row states the upstream gap it closes.

| Patch | What it does & why it exists |
|-------|------------------------------|
| `enable_local_agent_mode.nim` | Enables Claude Code / Local Agent Mode on the host. Several feature checks in the shared bundle return `unavailable` unless `process.platform` is `darwin`/`win32`; this rewrites them to `supported`, marks the capabilities this package ships Linux backends for (Code, plugins, Computer Use) as supported in the feature merger, and turns the Code preference defaults on. Cowork VM support is **not** forced - it follows upstream's native KVM probe - and GrowthBook rollout flags are **not** forced (opt in via [`growthbookOverrides`](#feature-flag-overrides-advanced)). Embedded regression guards assert the app keeps reporting the real platform (`linux`) to claude.ai and that upstream's native Linux Cowork path stays present |
| `fix_app_quit.nim` | The app hung on exit: after the `will-quit` cleanup handler runs, a second `app.quit()` is a no-op on Linux - uses `app.exit(0)` instead |
| `fix_browse_files_linux.nim` | The file dialog offers `openDirectory` only on macOS upstream; adds Linux (Electron supports it natively) |
| `fix_browser_tools_linux.nim` | Enables Chrome browser tools: repoints the native-messaging host to Claude Code's wrapper, extends browser discovery beyond upstream's Chrome+Edge (Chromium, Brave, Vivaldi, Opera), and adds Linux branches for extension auto-install and the DevTools opener - both still macOS/Windows-only upstream |
| `fix_builtin_mcp_browser_env.nim` | Built-in MCP servers run with a filtered env of `HOME,LOGNAME,PATH,SHELL,TERM,USER` - no display variables, fine on macOS, but on Linux the server can't open a browser for OAuth. Adds `DISPLAY`/Wayland/XDG/DBUS/`BROWSER`/`KDE_SESSION_VERSION` (without the last, `xdg-open` on KDE no-ops silently via its `kfmclient` fallback) ([#139](https://github.com/patrickjaja/claude-desktop-bin/issues/139)) |
| `fix_builtin_mcp_open_url_handler.nim` | Parent side of the M365 OAuth browser-open delegation: adds an `open-url` branch (https-only, → `shell.openExternal`) to the built-in MCP host's child-message handler - the same mechanism remote OAuth connectors use ([#139](https://github.com/patrickjaja/claude-desktop-bin/issues/139)) |
| `fix_office365_mcp_open_url.nim` | Child side: the bundled `office365-mcp` server posts `{type:"open-url"}` to the Electron parent instead of spawning `xdg-open`, which is unreliable inside the MCP child process on KDE (silent no-op → 300 s sign-in timeout) ([#139](https://github.com/patrickjaja/claude-desktop-bin/issues/139)) |
| `fix_cli_governor_memavailable.nim` | Computes CliGovernor memory pressure from `/proc/meminfo` `MemAvailable`. Upstream uses Electron's `free` = Linux `MemFree`, which excludes reclaimable page cache, so a healthy system reads ~5% free and triggers false pressure warnings ([#128](https://github.com/patrickjaja/claude-desktop-bin/issues/128)) |
| `fix_cowork_firmware_paths_linux.nim` | The Cowork VM capability probe hardcodes Debian firmware/virtiofsd paths, so on other distros Cowork reports "Download failed" / "requires QEMU" even with QEMU installed. Adds Fedora/RHEL/Arch OVMF and Arch/NixOS virtiofsd locations plus `CLAUDE_OVMF_CODE_PATH`/`CLAUDE_VIRTIOFSD_PATH` overrides for non-FHS setups ([#177](https://github.com/patrickjaja/claude-desktop-bin/issues/177)) |
| `fix_cowork_font.nim` | claude.ai initializes the chat-font preference only when the Chat view mounts; applies it to the Cowork tab too (it fell back to Serif) |
| `fix_cross_device_rename.nim` | Adds an EXDEV copy+delete fallback to `fs.rename()`: downloads land in `/tmp` (usually a separate tmpfs) and are renamed into `~/.config`, which fails across filesystems |
| `fix_detected_projects_linux.nim` | Project detection is gated to macOS and the VS Code/Cursor/Zed state-DB paths are hardcoded macOS locations; opens the gate and adds the Linux paths |
| `fix_dock_bounce.nim` | Upstream focus/attention calls translate to `DEMANDS_ATTENTION` taskbar flashing on KDE/GNOME; suppresses them |
| `fix_ion_dist_linux.nim` | The 3P config SPA's org-plugins mount path has only macOS/Windows entries; adds `/etc/claude-desktop/org-plugins` and a Linux display branch |
| `fix_marketplace_linux.nim` | Forces host-local mode for plugin operations on Linux and promotes `$HOME`-scoped CLI plugins to user scope ("Personal Plugins") |
| `fix_native_frame.nim` | Upstream builds the integrated titlebar only on Windows and gives Linux the native GTK frame; enables the integrated titlebar on Linux by default (opt out via `CLAUDE_NATIVE_TITLEBAR=1` / `--native-titlebar`) |
| `fix_open_in_editor_linux.nim` | "Open in VS Code / Cursor / Zed / Windsurf" gates on `getApplicationInfoForProtocol`, which answers only on macOS/Windows - Linux editors always showed as not installed. Answers it via an `xdg-mime` shim |
| `fix_process_argv_renderer.nim` | The preload exposes a `process` object without `argv`; the Claude Code SDK web bundle calls `process.argv.includes()`, and the TypeError blocked Dispatch responses from rendering. Injects an empty `argv` |
| `fix_renderer_gone_suppressed_log.nim` | Logs main-webview renderer deaths upstream silently suppresses - a kernel OOM SIGKILL arrives as reason `killed` and left no trace in `main.log` ([#128](https://github.com/patrickjaja/claude-desktop-bin/issues/128)) |
| `fix_sensitive_dirs_linux.nim` | The sandbox sensitive-directories block list has macOS and Windows entries but none for Linux; adds `.local/share/keyrings`, `.pki`, `.config/autostart` |
| `fix_startup_settings.nim` | Session-restore handling for "Start at login": hides the main window when the launch comes from session restore, and keeps autostart entries per-profile. The base XDG autostart toggle is native upstream (asserted by embedded guards) |
| `fix_tray_dbus.nim` | Serializes tray destroy/recreate (mutex + cleanup delay) - the DBus/StatusNotifier race left ghost tray icons - and drops the recreate-on-theme-change (the Linux tray icon is static) |
| `fix_tray_icon_theme.nim` | Always uses the light tray glyph (`TrayIconLinux-Dark.png`) on Linux: upstream's heuristic only does so on GNOME/dark themes, but Linux tray areas are dark regardless of desktop theme, leaving the icon invisible on light themes |
| `fix_updater_state_linux.nim` | Auto-update is off on Linux, so the updater idles without the `version` fields the frontend reads unchecked (TypeError); adds empty defaults |
| `fix_utility_process_kill.nim` | The post-timeout fallback kill re-sends SIGTERM instead of SIGKILL, so a stuck UtilityProcess survived and blocked exit; sends `SIGKILL` |
| `fix_window_bounds.nim` | Child-view geometry doesn't track window resize on Linux (stale bounds after maximize/snap/fullscreen); re-fits the content view, and blurs Quick Entry before hiding it |

### Regression guards

These change nothing in the bundle. Each asserts that native Linux behavior the app relies on is still present in a new upstream release and fails the build (`exit 1`) if it disappeared - so a regression is caught at build time, not by users.

| Patch | What it asserts |
|-------|-----------------|
| `fix_enterprise_config_linux.nim` | The main bundle still reads `/etc/claude-desktop/managed-settings.json` with the hardened native reader - the basis of [3P/enterprise inference](#third-party--enterprise-inference) on Linux |
| `fix_enterprise_config_linux_pre.nim` | The same reader in the boot bundle (`index.pre.js`), which decides 1P-vs-3P mode before the main process starts |
| `fix_native_frame_renderer.nim` | The title-bar component still returns `null` for the main window - a drag region there absorbs clicks on UI buttons in integrated-titlebar mode and must not come back |

`enable_local_agent_mode.nim` and `fix_startup_settings.nim` embed further guards inside their active patches: real-platform reporting to claude.ai, the native Linux Cowork bundle path, SSH MCP passthrough, and the native XDG autostart read/write.

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
| `--1p` / `--3p` | Select personal claude.ai (1P) vs [third-party inference](docs/third-party-inference.md) (3P) mode by persisting the upstream `deploymentMode` key; replaces the removed upstream `--boot-1p-once` flag. See [switching back to 1P](docs/third-party-inference.md#common-gotchas) |
| `--native-titlebar` | Use the native window frame instead of the integrated titlebar (same as `CLAUDE_NATIVE_TITLEBAR=1`) |
| `--no-systemd-scope` | Skip the `systemd --user --scope` wrapper for this launch (same as `CLAUDE_DISABLE_SYSTEMD_SCOPE=1`) |
| `--diagnose` | Print session type, portal status, and hotkey state for issue reports |
| `--integrate` / `--unintegrate` | Register / remove the `claude://` handler and menu entry (AppImage only; happens automatically on launch) |

## Environment Variables

`claude-desktop` reads a handful of env vars at launch (all optional). The ones people reach for most:

| Variable | Values | Description |
|----------|--------|-------------|
| `CLAUDE_DISABLE_GPU` | `1`, `full` | Fix white screen on some GPU/driver combos ([#13](https://github.com/patrickjaja/claude-desktop-bin/issues/13)). `1` disables compositing only, `full` disables GPU entirely |
| `CLAUDE_PROFILE` | name | Select a [profile](#multiple-profiles) by name (also `claude-desktop-NAME` / `--profile=NAME`) |
| `CLAUDE_NATIVE_TITLEBAR` | `1` | Restore the native window frame instead of the integrated titlebar (same as `--native-titlebar`) |
| `CLAUDE_USE_XWAYLAND` | `1` | Force XWayland instead of native Wayland. Also fixes "app exits after seconds" GPU crashes ([#180](https://github.com/patrickjaja/claude-desktop-bin/issues/180), see [wayland.md](wayland.md)) |
| `CLAUDE_PASSWORD_STORE` | backend, `auto` | Force the Chromium keyring backend (`gnome-libsecret`, `kwallet6`, `basic`, ...). Default: on desktops Chromium gives no keyring backend (Hyprland, sway, XFCE, ...), a running Secret Service is used automatically so sign-in persists ([#191](https://github.com/patrickjaja/claude-desktop-bin/issues/191)). `auto` disables that detection |

Set permanently in `~/.bashrc` / `~/.zshrc`, or pass per-launch: `CLAUDE_DISABLE_GPU=1 claude-desktop`

**Full list** (profile/config dirs, Vulkan, menu bar, DevTools, systemd-scope, Electron overrides, …) → **[docs/environment-variables.md](docs/environment-variables.md)**.

## Feature Flag Overrides (advanced)

Claude Desktop gates many features behind server-side GrowthBook flags with no built-in local override. This package adds one: **`~/.config/Claude/claude-desktop-bin.jsonc`** (per-profile: the profile's userData dir; auto-created with a commented template on first launch). It is the same config file the [Custom Themes](#custom-themes) use - one file for both. A legacy `claude-desktop-bin.json` next to it keeps working and is merged in (the `.jsonc` wins per key). Uncomment an entry to activate it - comments are allowed:

```jsonc
{
  "growthbookOverrides": {
    "1129419822": true   // ENABLE_TOOL_SEARCH - tool search in local agent sessions
  }
}
```

Overrides apply on every flag load (startup + periodic refresh, no restart needed) and win over the server rollout; active overrides are logged to `logs/claude-patches.log`. `true`/`false` for switches, numbers/strings/objects for value flags.

**Full flag catalog:** the auto-created template lists *every* GrowthBook flag the app reads from its feature store, each commented out with a short description - browse it here: **[docs/claude-desktop-bin.jsonc](docs/claude-desktop-bin.jsonc)**. It reflects the version noted in the file header; CI verifies it stays in sync with the shipped template.

**Scope and caveats:** flag IDs are Anthropic-internal and can vanish or change meaning in any release; this is unsupported expert territory - if the app misbehaves, empty the file first. The Computer Use and Hardware Buddy patches force their own enable gates directly and don't consult this file, and server-side account capabilities can't be overridden locally at all.

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

Computer Use patches emit `[claude-cu] diagnostics:` lines showing the detected session, available/missing tools, and screenshot cascade. They land in `~/.config/Claude/logs/claude-patches.log` (and on stderr when launched from a terminal) - share that log file when reporting Computer Use issues. The official build discards plain `console.log` output, so the old "run from a terminal and copy the output" advice only shows Chromium noise.

## Known Limitations

- **App identity on Wayland.** `xdg-desktop-portal` resolves unsandboxed apps via the systemd user scope. We launch under `app-claude-*.scope` and install the `.desktop` as `claude.desktop`; the id `claude` matches Chromium's autogenerated scope, so WM_CLASS, Wayland `app_id`, and the `.desktop` basename all agree. KDE global shortcuts and persistent portal authorizations attach to that id and survive across sessions.
  - If you had `com.anthropic.claude-desktop.desktop` pinned from an earlier release, **re-pin once**.
  - Custom X11/Wayland WM rules matching `Claude` or `com.anthropic.claude-desktop` need updating to `claude` (named profiles add a `-<profile>` suffix).
  - GNOME shell-extension blacklists (Rounded Window Corners, Unite, Blur My Shell) referencing `com.anthropic.claude-quick-entry` should become `claude-quick-entry`.
  - **NixOS** doesn't use `systemd-run --scope`; portal identity may not resolve on GNOME Wayland - use `--install-gnome-hotkey`.
  - **Sandboxes/containers** without a reachable user-systemd (bwrap, distrobox, restricted Flatpaks) auto-skip the scope wrap; force it with `--no-systemd-scope` / `CLAUDE_DISABLE_SYSTEMD_SCOPE=1` if the socket exists but is unreachable ([#89](https://github.com/patrickjaja/claude-desktop-bin/issues/89)).
- **Computer Use targets the primary monitor** - screenshots/clicks can be retargeted with `switch_display`; the teach overlay stays on the primary display. See [Computer Use](#computer-use).
- **CoworkSpaces are local-only** on every platform (no account-sync) - a set created on macOS/Windows won't transfer to Linux. Upstream behavior.

## Automation

CI polls the official apt Packages index every 2 hours, downloads the latest official `.deb` (verifying GPG + SHA256), extracts and patches its `app.asar`, and **validates every patch in Docker** (`makepkg` in `archlinux:base-devel`) before publishing. Each patch exits 1 if its pattern doesn't match, so a broken package never reaches users - the pipeline stops with a clear `[FAIL]` and the AUR/repo packages stay on the last-good version until patches are updated.

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
