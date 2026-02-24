#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Disable auto-updater on Linux.

The Windows Claude Desktop package includes Squirrel-based auto-update logic.
On Linux, this can trigger false "Update downloaded" notifications because:
- The isInstalled check (s$e) returns true for our repackaged app
- Electron's autoUpdater may fire stale events from the Windows package

This patch makes the isInstalled function return false on Linux, which:
- Hides update-related menu items (visible: s$e())
- Prevents the auto-update initialization from running
- Stops false "Update heruntergeladen" (update downloaded) notifications
- Leaves macOS and Windows behavior unchanged

Usage: python3 fix_disable_autoupdate.py <path_to_index.js>
"""

import sys
import os
import re


def patch_disable_autoupdate(filepath):
    """Disable auto-updater on Linux by making isInstalled return false."""

    print(f"=== Patch: fix_disable_autoupdate ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content
    failed = False

    # Patch: Make the isInstalled function return false on Linux
    #
    # Original pattern (minified variable names change between versions):
    #   function XXX(){if(process.platform!=="win32")return YY.app.isPackaged;...
    #
    # We insert a Linux early-return before the existing platform check:
    #   function XXX(){if(process.platform==="linux")return!1;if(process.platform!=="win32")return YY.app.isPackaged;...
    #
    # Function name and electron var may contain $ (valid JS identifier char).
    # Use [\w$]+ to match any JS identifier.
    pattern = rb'(function [\w$]+\(\)\{)(if\(process\.platform!=="win32"\)return [\w$]+\.app\.isPackaged)'

    replacement = rb'\1if(process.platform==="linux")return!1;\2'

    content, count = re.subn(pattern, replacement, content)
    if count >= 1:
        print(f"  [OK] isInstalled Linux gate: {count} match(es)")
    else:
        print(f"  [FAIL] isInstalled function: 0 matches")
        failed = True

    if failed:
        print("  [FAIL] Required patterns did not match")
        return False

    # Write back if changed
    if content != original_content:
        with open(filepath, 'wb') as f:
            f.write(content)
        print("  [PASS] Auto-updater disabled on Linux")
        return True
    else:
        print("  [WARN] No changes made (pattern may have already been applied)")
        return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_disable_autoupdate(sys.argv[1])
    sys.exit(0 if success else 1)
