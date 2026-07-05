# Computer Use

**Our exclusive feature - not part of the official Linux beta.** Claude Desktop's built-in Computer Use MCP server exposes 27 tools for desktop automation (screenshot, click, type, scroll, drag, clipboard, and more). The **learn tools** (`learn_application`, `learn_screen_region`) generate interactive overlay tutorials that walk through any application's UI step by step.

Example prompt: *"Can you use computer use MCP to explain me the PhpStorm application?"*

**How it works on Linux:** upstream Computer Use is macOS-only - gated behind `process.platform==="darwin"`, macOS TCC permissions, and a native Swift executor. The patch ([`fix_computer_use_linux.nim`](../patches/fix_computer_use_linux.nim)) removes the platform gates, routes both upstream executor factories to an injected Linux executor, bypasses TCC with a no-op `{granted: true}`, and auto-detects your session type to use the right backend: the bundled [`x11-bridge`](https://github.com/patrickjaja/x11-bridge) on X11 / XWayland, the bundled [`kwin-portal-bridge`](https://github.com/patrickjaja/kwin-portal-bridge) on KDE Wayland, and `ydotool` plus `grim`/`gnome-screenshot`/portal on other Wayland (wlroots / GNOME). Install the packages for your session from your distro's [Installation](../README.md#installation) section, or see [Computer Use dependencies](computer-use-dependencies.md) for the full matrix and `ydotool` setup.

**Notes:**
- **Primary monitor only.** Screenshots, clicks, and the teach overlay target the primary display; use `switch_display` to target another for screenshots/clicks (teach overlay stays on primary).
- **App discovery** for the teach overlay scans `.desktop` files from `/usr/share/applications`, `~/.local/share/applications`, and Flatpak dirs, registering each with multiple name variants for flexible matching.
- **Teach overlay** stays interactive but blocks clicks to apps behind it during a tour (Electron's `setIgnoreMouseEvents` is [broken on X11](https://github.com/electron/electron/issues/16777)).

See [CLAUDE_BUILT_IN_MCP.md](../baseline/CLAUDE_BUILT_IN_MCP.md#14-computer-use) for the full tool reference, and [Computer Use dependencies](computer-use-dependencies.md) for the package matrix, the KDE/GNOME portal behavior notes, `COWORK_SCREENSHOT_CMD`, and `ydotool` v1.0+ setup.

**Debugging:** Computer Use patches emit `[claude-cu] diagnostics:` lines at startup showing the detected session, available/missing tools, and screenshot cascade - run `claude-desktop` from a terminal and share that output when reporting Computer Use issues. See also [Debugging](../README.md#debugging).
