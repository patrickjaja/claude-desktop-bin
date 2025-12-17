#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Patch Claude Desktop to fix startup settings on Linux.

On Linux, Electron's app.getLoginItemSettings() returns undefined values for
openAtLogin and executableWillLaunchAtLogin, causing validation errors.
This patch adds a Linux platform check to return false immediately.

Linux autostart is typically handled via .desktop files in ~/.config/autostart/
which is outside the app's control anyway.

Usage: python3 fix_startup_settings.py <path_to_index.js>
"""

import sys
import os
import re


def patch_startup_settings(filepath):
    """Patch startup settings to handle Linux correctly."""

    print(f"=== Patch: fix_startup_settings ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content
    patches_applied = 0

    # Pattern 1: isStartupOnLoginEnabled function
    # Add Linux platform check before the existing env var check
    pattern1 = rb'isStartupOnLoginEnabled\(\)\{if\(process\.env\.CLAUDE_AVOID_READING_LOGING_ITEM_SETTINGS\)return!1;'
    replacement1 = b'isStartupOnLoginEnabled(){if(process.platform==="linux"||process.env.CLAUDE_AVOID_READING_LOGING_ITEM_SETTINGS)return!1;'

    content, count1 = re.subn(pattern1, replacement1, content)
    if count1 > 0:
        patches_applied += count1
        print(f"  [OK] isStartupOnLoginEnabled: {count1} match(es)")
    else:
        print(f"  [FAIL] isStartupOnLoginEnabled: 0 matches")

    # Pattern 2: setStartupOnLoginEnabled function - make it a no-op on Linux
    # Find the function and add early return for Linux
    pattern2 = rb'setStartupOnLoginEnabled\((\w+)\)\{re\.debug\('

    def replacement2_func(m):
        arg_var = m.group(1)
        return b'setStartupOnLoginEnabled(' + arg_var + b'){if(process.platform==="linux")return;re.debug('

    content, count2 = re.subn(pattern2, replacement2_func, content)
    if count2 > 0:
        patches_applied += count2
        print(f"  [OK] setStartupOnLoginEnabled: {count2} match(es)")
    else:
        print(f"  [INFO] setStartupOnLoginEnabled: 0 matches (optional)")

    # Check results
    if patches_applied == 0:
        print(f"  [FAIL] No patterns matched")
        return False

    # Write back if changed
    if content != original_content:
        with open(filepath, 'wb') as f:
            f.write(content)
        print("  [PASS] Startup settings patched successfully")
        return True
    else:
        print("  [WARN] No changes made")
        return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_startup_settings(sys.argv[1])
    sys.exit(0 if success else 1)
