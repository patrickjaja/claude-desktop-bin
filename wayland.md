# Wayland Troubleshooting

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
