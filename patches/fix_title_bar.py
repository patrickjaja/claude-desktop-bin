#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/renderer/main_window/assets/MainWindowPage-*.js
# @patch-type: python
"""
Patch Claude Desktop to show internal title bar on Linux.

v1.1.886+ code structure:
  function _e({isMainWindow:e,...}){
    const[a,s]=c.useState(!1);
    if(c.useEffect(...),[]),!W&&e)return <drag-div>;  // Early return 1
    if(a&&e)return null;                              // Early return 2
    // ... render full title bar
  }

  Where:
  - W = process.platform==="win32" (true on Windows, false on Linux)
  - e = isMainWindow
  - a = state from onTopBarStateChanged

  This patch replaces both conditions with "false&&" prefix to disable them:
  - !W&&e -> false&&!W&&e (always false)
  - a&&e -> false&&a&&e (always false)

  Result: Both early returns are disabled, title bar always renders.

Usage: python3 fix_title_bar.py <path_to_MainWindowPage-*.js>
"""

import sys
import os
import re


def patch_title_bar(filepath):
    """Patch the title bar detection to show on Linux."""

    print(f"=== Patch: fix_title_bar ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content
    patches_applied = 0

    # Pattern 1: Disable first early return (Linux drag-div return)
    # Change: []),!W&&e)return -> []),false&&!W&&e)return
    pattern1 = rb'\[\]\),!(\w+)&&(\w+)\)return'
    replacement1 = rb'[]),false&&!\1&&\2)return'

    content, count1 = re.subn(pattern1, replacement1, content)
    if count1 > 0:
        patches_applied += count1
        print(f"  [OK] first early return: disabled with false&& prefix ({count1} match)")

    # Pattern 2: Disable second early return (native frame null return)
    # Change: ;if(a&&e)return null -> ;if(false&&a&&e)return null
    pattern2 = rb';if\((\w+)&&(\w+)\)return null'
    replacement2 = rb';if(false&&\1&&\2)return null'

    content, count2 = re.subn(pattern2, replacement2, content, count=1)
    if count2 > 0:
        patches_applied += count2
        print(f"  [OK] second early return: disabled with false&& prefix ({count2} match)")

    # Pattern 3: Old structure (pre-v1.1.886)
    if patches_applied == 0:
        pattern3 = rb'if\(!([a-zA-Z_]\w*)\s*&&\s*([a-zA-Z_]\w*)\)return null'
        replacement3 = rb'if(false&&!\1&&\2)return null'
        content, count3 = re.subn(pattern3, replacement3, content)
        if count3 > 0:
            patches_applied += count3
            print(f"  [OK] old pattern: disabled with false&& prefix ({count3} match)")

    if patches_applied == 0:
        print(f"  [FAIL] No patterns matched")
        return False

    if content != original_content:
        with open(filepath, 'wb') as f:
            f.write(content)
        print("  [PASS] Title bar patched successfully")
        return True
    else:
        print("  [WARN] No changes made")
        return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_MainWindowPage-*.js>")
        sys.exit(1)

    success = patch_title_bar(sys.argv[1])
    sys.exit(0 if success else 1)
