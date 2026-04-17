# Wayland Troubleshooting

## Quick Entry hotkey not firing on GNOME

On GNOME Wayland the `xdg-desktop-portal` GlobalShortcuts flow only works if
the user explicitly approves a notification/dialog at the moment Claude first
calls `BindShortcuts`. In practice the notification is easy to miss, and
Electron's `globalShortcut.register()` returns `true` whether or not the
approval went through — so the hotkey silently doesn't fire and the symptom
is "only works when Claude has focus" (issue [#38](https://github.com/patrickjaja/claude-desktop-bin/issues/38)).

The reliable fix on GNOME is to bind a GNOME custom keybinding directly to
`claude-desktop --toggle-quick-entry` — a CLI trigger that the running Claude
instance responds to through Electron's single-instance mechanism, bypassing
the portal entirely.

### Install the GNOME hotkey

```bash
claude-desktop --install-gnome-hotkey                 # default Ctrl+Alt+Space
claude-desktop --install-gnome-hotkey '<Super>space'  # or any accelerator
```

Accelerator syntax is the same as GNOME Settings → Keyboard (`<Primary>` = Ctrl,
`<Shift>`, `<Alt>`, `<Super>`, letters/keys verbatim). Safe to re-run to change
the accelerator; preserves any other custom keybindings you have.

```bash
claude-desktop --uninstall-gnome-hotkey               # remove
```

Verify with:

```bash
gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings
# Should include '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/claude-desktop-quick-entry/'
```

### First launch with hotkey

`claude-desktop --toggle-quick-entry` on a cold start launches Claude and
opens Quick Entry as soon as the app is ready (≈500 ms). No separate launch
step needed.

### Diagnose

```bash
claude-desktop --diagnose
```

Prints session type, Electron version, portal version, whether the app has
completed a portal `BindShortcuts` approval, and whether the GNOME custom
keybinding slot is installed. Paste the output directly into issue reports.

### "Quick Entry flashes on screen then instantly disappears"

Classic Wayland focus-stealing-prevention symptom. When `Po.show()` is called
from a background context, Mutter won't transfer focus; Electron emits `blur`
within a few hundred milliseconds because the logical focus state just changed;
the upstream dismiss handler runs before you can type. Fixed by
`patches/fix_quick_entry_wayland_blur_guard.py` — blurs within 500 ms of a
fresh `show` are ignored. Blur-dismiss on deliberate click-outside still works
normally after the grace window. No user action required — the patch is
included in every build.

## Global Shortcut Not Working (KDE Plasma)

Electron registers shortcuts via `kglobalaccel`. Stale entries from crashed or killed sessions block new registrations silently.

### List registered Electron shortcuts

```bash
gdbus call --session --dest org.kde.kglobalaccel \
  --object-path /component/electron \
  --method org.kde.kglobalaccel.Component.allShortcutInfos
```

### Remove a stale shortcut

```bash
gdbus call --session --dest org.kde.kglobalaccel \
  --object-path /kglobalaccel \
  --method org.kde.KGlobalAccel.unregister \
  'electron' '<action-id>'
```

The `<action-id>` is the first field from the list output (e.g. `5DB35CB47F569991B62AF33B8F5CA3A0-Ctrl+Alt+Space`).

### Remove all stale Electron shortcuts at once

```bash
gdbus call --session --dest org.kde.kglobalaccel \
  --object-path /component/electron \
  --method org.kde.kglobalaccel.Component.allShortcutInfos 2>/dev/null \
| grep -oP "'[A-F0-9]+-[^']+'" | tr -d "'" | while read id; do
  gdbus call --session --dest org.kde.kglobalaccel \
    --object-path /kglobalaccel \
    --method org.kde.KGlobalAccel.unregister 'electron' "$id"
done
```

After clearing, restart Claude Desktop. The portal will prompt to approve the shortcut again.
