# Environment Variables

These environment variables tune `claude-desktop` at launch. All are optional; with none set, `claude-desktop` just launches the default profile.

| Variable | Values | Description |
|----------|--------|-------------|
| `CLAUDE_PROFILE` | name | Select a [profile](../README.md#multiple-profiles) by name. Inherited by Electron and Claude Code so per-profile sockets and config dirs are picked up everywhere |
| `CLAUDE_PROFILE_QUIET` | `1` | Suppress the "no per-profile WM identity" hint when `CLAUDE_PROFILE` is set without a matching `--create-profile` |
| `CLAUDE_CONFIG_DIR` | path | Override Claude Code's config dir. Auto-set by the launcher when `CLAUDE_PROFILE` is active |
| `CLAUDE_DISABLE_GPU` | `1`, `full` | Fix white screen on some GPU/driver combos ([#13](https://github.com/patrickjaja/claude-desktop-bin/issues/13)). `1` disables compositing only, `full` disables GPU entirely |
| `CLAUDE_USE_XWAYLAND` | `1` | Force XWayland instead of native Wayland |
| `CLAUDE_ENABLE_VULKAN` | `1` | Keep Vulkan enabled on native Wayland. Default off: Chromium (Electron 42) refuses to pair Vulkan with `--ozone-platform=wayland`, causing a silent no-window startup. Only affects Wayland |
| `CLAUDE_MENU_BAR` | `auto`, `visible`, `hidden` | Menu bar visibility (default: `auto`, toggle with Alt) |
| `CLAUDE_DEV_TOOLS` | `detach` | Open Chromium DevTools on launch |
| `CLAUDE_ELECTRON` | path | Override Electron binary path. Electron auto-loads the `resources/app.asar` next to the binary |
| `CLAUDE_NATIVE_TITLEBAR` | `1` | Restore the native window frame (default: integrated titlebar). Equivalent to `--native-titlebar`. See [#100](https://github.com/patrickjaja/claude-desktop-bin/pull/100) |
| `CLAUDE_DISABLE_SYSTEMD_SCOPE` | `1` | Skip the `systemd-run --user --scope` wrapper. Use in sandboxes (bwrap, distrobox) where the systemd private socket is unreachable. Equivalent to `--no-systemd-scope`. See [#89](https://github.com/patrickjaja/claude-desktop-bin/issues/89) |
| `CLAUDE_PASSWORD_STORE` | backend, `auto` | Force Chromium's `--password-store=<backend>` (`gnome-libsecret`, `kwallet6`, `basic`, ...). Without it, the launcher adds `gnome-libsecret` automatically when the desktop gets no keyring backend from Chromium (Hyprland, sway, river, niri, XFCE, LXQt, ...) and a Secret Service (`org.freedesktop.secrets`) is running or activatable - this makes sign-in persist across launches. `auto` disables the detection and keeps Chromium's own choice. An explicit `--password-store=...` launch argument always wins. Switching away from `basic_text` asks you to sign in once more. See [#191](https://github.com/patrickjaja/claude-desktop-bin/issues/191) |
| `ELECTRON_ENABLE_LOGGING` | `1` | Log Electron main process to stderr |

Set permanently in `~/.bashrc` / `~/.zshrc`, or pass per-launch: `CLAUDE_DISABLE_GPU=1 claude-desktop`

## Feature-specific variables

A few variables belong to specific features and are documented alongside them:

- `COWORK_SCREENSHOT_CMD` - override Computer Use screenshot auto-detection. See [Computer Use dependencies](computer-use-dependencies.md#custom-screenshot-command).
- `CLAUDE_VIRTIOFSD_PATH` - path to a system `virtiofsd` binary for the Cowork VM capability probe. Checked before all fixed candidate paths. Needed only when virtiofsd lives outside the probed locations (`/usr/libexec`, `/usr/lib`, `/usr/lib/qemu`, `/run/current-system/sw/bin`, `/usr/bin`) - e.g. AppImage on NixOS. The Nix flake package sets it automatically; the bundled virtiofsd is only ever used on Ubuntu 22.x ([#177](https://github.com/patrickjaja/claude-desktop-bin/issues/177)).
- `CLAUDE_OVMF_CODE_PATH` - path to an OVMF/AAVMF UEFI *CODE* firmware image for the Cowork VM capability probe, checked before the fixed `/usr/share/...` candidates. The matching `*_VARS*` file must sit next to it with the same name shape (the app derives it by replacing `OVMF_CODE` -> `OVMF_VARS` / `AAVMF_CODE` -> `AAVMF_VARS` in the filename). The Nix flake package sets it automatically ([#177](https://github.com/patrickjaja/claude-desktop-bin/issues/177)).

Both Cowork variables must reach the **app process**, not just your shell - a `~/.bashrc` export only covers terminal launches. For icon/GUI launches put them in the session environment (NixOS: `environment.sessionVariables = { CLAUDE_VIRTIOFSD_PATH = "${pkgs.virtiofsd}/bin/virtiofsd"; ... }`; elsewhere: `~/.config/environment.d/`). Flake users don't need any of this - the wrapper bakes both in. `claude-desktop --diagnose` honors them too, so a wrong path is immediately visible.

## See also

- [Command-line flags](../README.md#command-line-flags) - launch flags this project adds on top of the official build (several have env-var equivalents above).
- [Debugging](../README.md#debugging) - how to combine `CLAUDE_DEV_TOOLS` + `ELECTRON_ENABLE_LOGGING` for verbose logs.
