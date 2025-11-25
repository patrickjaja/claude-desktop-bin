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

    print(f"Patching Quick Entry position in: {filepath}")

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content
    patches_applied = 0

    # There are TWO functions that determine Quick Entry position:
    # 1. dTe() - primary function, uses saved position or falls back to pTe()
    #    It also has a fallback to getPrimaryDisplay() inside
    # 2. pTe() - fallback function that creates initial position
    #
    # We need to patch BOTH to always use cursor position

    # Patch 1: In pTe() function - the fallback position generator
    # Original: function pTe(){const t=ce.screen.getPrimaryDisplay(),...}
    pattern1 = rb'(function pTe\(\)\{const t=ce\.screen\.)getPrimaryDisplay\(\)'
    replacement1 = rb'\1getDisplayNearestPoint(ce.screen.getCursorScreenPoint())'
    content, count1 = re.subn(pattern1, replacement1, content)
    if count1 > 0:
        patches_applied += count1
        print(f"  Patched pTe(): {count1} occurrence(s)")

    # Patch 2: In dTe() function - the main position function
    # It has: r||(r=ce.screen.getPrimaryDisplay())
    # We want: r||(r=ce.screen.getDisplayNearestPoint(ce.screen.getCursorScreenPoint()))
    pattern2 = rb'r\|\|\(r=ce\.screen\.getPrimaryDisplay\(\)\)'
    replacement2 = rb'r||(r=ce.screen.getDisplayNearestPoint(ce.screen.getCursorScreenPoint()))'
    content, count2 = re.subn(pattern2, replacement2, content)
    if count2 > 0:
        patches_applied += count2
        print(f"  Patched dTe() fallback: {count2} occurrence(s)")

    # Patch 3: Override the entire position logic to ALWAYS use cursor position
    # The dTe function tries to restore saved position which might be on wrong monitor
    # We'll make it always calculate fresh position based on cursor
    # Replace the whole dTe function to always call pTe (which now uses cursor position)
    pattern3 = rb'function dTe\(\)\{const t=hn\.get\("quickWindowPosition",null\),e=ce\.screen\.getAllDisplays\(\);if\(!\(t&&t\.absolutePointInWorkspace&&t\.monitor&&t\.relativePointFromMonitor\)\)return pTe\(\)'
    replacement3 = rb'function dTe(){return pTe()/*patched to always use cursor position*/;const t=hn.get("quickWindowPosition",null),e=ce.screen.getAllDisplays();if(!(t&&t.absolutePointInWorkspace&&t.monitor&&t.relativePointFromMonitor))return pTe()'
    content, count3 = re.subn(pattern3, replacement3, content)
    if count3 > 0:
        patches_applied += count3
        print(f"  Patched dTe() to always use cursor position: {count3} occurrence(s)")

    if content != original_content:
        with open(filepath, 'wb') as f:
            f.write(content)
        print(f"Quick Entry position patches applied: {patches_applied} total")
        return True
    else:
        print("Warning: No Quick Entry position patches applied (pattern not found)")
        return False


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    filepath = sys.argv[1]
    if not os.path.exists(filepath):
        print(f"Error: File not found: {filepath}")
        sys.exit(1)

    patch_quick_entry_position(filepath)
    # Always exit 0 - patch is best-effort
    sys.exit(0)
