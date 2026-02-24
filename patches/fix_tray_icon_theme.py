#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Patch Claude Desktop to use correct tray icon on Linux.

On Windows, the app checks nativeTheme.shouldUseDarkColors to select the
appropriate icon (light icon for dark theme, dark icon for light theme).
On Linux, it always uses TrayIconTemplate.png (dark icon).

Linux system trays are almost universally dark (GNOME, KDE, etc.), so we
always need TrayIconTemplate-Dark.png (the light icon) regardless of the
desktop theme setting.

Usage: python3 fix_tray_icon_theme.py <path_to_index.js>
"""

import sys
import os
import re


def patch_tray_icon_theme(filepath):
    """Patch tray icon selection to respect theme on Linux."""

    print(f"=== Patch: fix_tray_icon_theme ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content

    # Pattern: The tray icon selection logic
    # Original: Si?e=de.nativeTheme.shouldUseDarkColors?"Tray-Win32-Dark.ico":"Tray-Win32.ico":e="TrayIconTemplate.png"
    # We want to change the Linux branch to also check the theme
    #
    # The variable names:
    # - Si = isWindows check
    # - de = electron module
    # - e = icon filename variable

    # Match the pattern with flexible variable names
    # Variable names may contain $ (valid JS identifier), so use [\w$]+
    pattern = rb'([\w$]+)\?([\w$]+)=([\w$]+)\.nativeTheme\.shouldUseDarkColors\?"Tray-Win32-Dark\.ico":"Tray-Win32\.ico":\2="TrayIconTemplate\.png"'

    def replacement(m):
        is_win_var = m.group(1)  # Ln
        icon_var = m.group(2)     # e
        electron_var = m.group(3) # $e
        # On Windows: use .ico files with theme check
        # On Linux: always use light icon (Dark.png) since trays are universally dark
        return (is_win_var + b'?' + icon_var + b'=' + electron_var +
                b'.nativeTheme.shouldUseDarkColors?"Tray-Win32-Dark.ico":"Tray-Win32.ico":' +
                icon_var + b'="TrayIconTemplate-Dark.png"')

    content, count = re.subn(pattern, replacement, content)

    if count > 0:
        print(f"  [OK] tray icon theme logic: {count} match(es)")
    else:
        print(f"  [FAIL] tray icon theme logic: 0 matches")
        return False

    # Write back if changed
    if content != original_content:
        with open(filepath, 'wb') as f:
            f.write(content)
        print("  [PASS] Tray icon theme patched successfully")
        return True
    else:
        print("  [WARN] No changes made")
        return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_tray_icon_theme(sys.argv[1])
    sys.exit(0 if success else 1)
