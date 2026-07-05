# Computer Use dependencies

[Computer Use](../README.md#computer-use) auto-detects your session at runtime and calls the matching tools. The per-distro package lists are inlined in each [Installation](../README.md#installation) section; this page is the full reference - the complete matrix, the portal/screenshot behavior notes, and the `ydotool` setup that Wayland needs.

Check your session type (`echo $XDG_SESSION_TYPE`) and desktop (`echo $XDG_CURRENT_DESKTOP`), then install the matching packages.

| Distro | X11 / XWayland | Wayland - Sway/Hyprland/Niri | Wayland - GNOME | Wayland - KDE Plasma |
|--------|----------------|-------------------------|-----------------|----------------------|
| **Arch** | *none - bundled bridge* | `ydotool grim jq` (+`hyprland` on Hyprland) | `ydotool xdotool glib2 gnome-screenshot imagemagick python-gobject gst-plugin-pipewire` | *none - bundled bridge* |
| **Debian/Ubuntu** | *none - bundled bridge* | `ydotool grim jq` (+`hyprland`) | `ydotool xdotool libglib2.0-bin gnome-screenshot imagemagick python3-gi gstreamer1.0-pipewire` | *none - bundled bridge* |
| **Fedora/RHEL** | *none - bundled bridge* | `ydotool grim jq` (+`hyprland`) | `ydotool xdotool glib2 gnome-screenshot ImageMagick python3-gobject pipewire-gstreamer` | *none - bundled bridge* |

> **X11 / XWayland:** the bundled [`x11-bridge`](https://github.com/patrickjaja/x11-bridge) handles input, screenshots, and window activation natively - no extra packages. It is a fully-static Rust binary (no glibc floor, runs on every distro). This first-party backend replaces the old `xdotool` / `scrot` / `imagemagick` / `wmctrl` / `gnome-screenshot` X11 tools; there is no third-party fallback on X11.
>
> **GNOME on XWayland:** the `xdotool` / `imagemagick` in the GNOME column are the XWayland fallback for GNOME sessions running Claude Desktop under XWayland; GNOME-native Wayland input uses `ydotool` and screenshots use the portal / `gnome-screenshot`.
>
> **KDE Plasma Wayland:** the bundled [`kwin-portal-bridge`](https://github.com/patrickjaja/kwin-portal-bridge) handles input, screenshots, clipboard, and display info natively via XDG portals - no extra packages. One consent prompt per session. Falls back to `ydotool` + `spectacle` if unavailable.
>
> **GNOME 46+** (Ubuntu 25.10+, Fedora 40+): screenshots use the XDG ScreenCast portal with PipeWire restore tokens - one permission dialog, then silent (needs `python-gobject`/`python3-gi` + `gst-plugin-pipewire`). Falls back to `gnome-screenshot` / `gdbus`. Set flat mouse accel for accurate clicks: `gsettings set org.gnome.desktop.peripherals.mouse accel-profile flat`.
>
> <a id="custom-screenshot-command"></a>
> **Custom screenshot command:** set `COWORK_SCREENSHOT_CMD` to override auto-detection. Placeholders: `{FILE}`, `{X}`, `{Y}`, `{W}`, `{H}`. Example: `COWORK_SCREENSHOT_CMD='spectacle -b -n -r -o {FILE}'`

<a id="ydotool-setup"></a>
## ydotool setup (Wayland - GNOME, Sway, Hyprland, Niri)

Computer Use needs `ydotool` **v1.0+** and the `ydotoold` daemon for input on GNOME, Sway, Hyprland, and Niri Wayland. KDE Plasma does not need it.

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
