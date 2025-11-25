#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Patch Claude Desktop Quick Entry to spawn on the monitor where the cursor is.

The original code uses getPrimaryDisplay() for the fallback position, which
always spawns the Quick Entry window on the primary monitor (usually the
laptop screen). This patch changes it to use getDisplayNearestPoint() with
the cursor position, so the window appears on the monitor where the user
is currently working.

Usage: python3 fix_quick_entry_position.py <path_to_index.js>
"""

import sys
import os
import re


def patch_quick_entry_position(filepath):
    """Patch Quick Entry to spawn on cursor's monitor instead of primary display."""

    print(f"=== Patch: fix_quick_entry_position ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content
    failed = False

    # Patch 1: In pTe() function - the fallback position generator
    pattern1 = rb'(function pTe\(\)\{const t=ce\.screen\.)getPrimaryDisplay\(\)'
    replacement1 = rb'\1getDisplayNearestPoint(ce.screen.getCursorScreenPoint())'
    content, count1 = re.subn(pattern1, replacement1, content)
    if count1 > 0:
        print(f"  [OK] pTe() function: {count1} match(es)")
    else:
        print(f"  [FAIL] pTe() function: 0 matches, expected >= 1")
        failed = True

    # Patch 2: In dTe() function - the fallback display lookup
    pattern2 = rb'r\|\|\(r=ce\.screen\.getPrimaryDisplay\(\)\)'
    replacement2 = rb'r||(r=ce.screen.getDisplayNearestPoint(ce.screen.getCursorScreenPoint()))'
    content, count2 = re.subn(pattern2, replacement2, content)
    if count2 > 0:
        print(f"  [OK] dTe() fallback: {count2} match(es)")
    else:
        print(f"  [FAIL] dTe() fallback: 0 matches, expected >= 1")
        failed = True

    # Patch 3: Override dTe to always use cursor position (optional enhancement)
    pattern3 = rb'function dTe\(\)\{const t=hn\.get\("quickWindowPosition",null\),e=ce\.screen\.getAllDisplays\(\);if\(!\(t&&t\.absolutePointInWorkspace&&t\.monitor&&t\.relativePointFromMonitor\)\)return pTe\(\)'
    replacement3 = rb'function dTe(){return pTe()/*patched to always use cursor position*/;const t=hn.get("quickWindowPosition",null),e=ce.screen.getAllDisplays();if(!(t&&t.absolutePointInWorkspace&&t.monitor&&t.relativePointFromMonitor))return pTe()'
    content, count3 = re.subn(pattern3, replacement3, content)
    if count3 > 0:
        print(f"  [OK] dTe() override: {count3} match(es)")
    else:
        print(f"  [INFO] dTe() override: 0 matches (optional)")

    # Check results
    if failed:
        print("  [FAIL] Required patterns did not match")
        return False

    # Write back if changed
    if content != original_content:
        with open(filepath, 'wb') as f:
            f.write(content)
        print("  [PASS] Quick Entry position patched successfully")
        return True
    else:
        print("  [WARN] No changes made (patterns may have already been applied)")
        return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_quick_entry_position(sys.argv[1])
    sys.exit(0 if success else 1)
