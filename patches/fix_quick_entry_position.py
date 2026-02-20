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

    # Patch 1: In position function - the fallback position generator
    # Pattern matches: function FUNCNAME(){const t=ELECTRON.screen.getPrimaryDisplay()
    # Function names change between versions (pTe, lPe, etc.), electron var changes (ce, de, etc.)
    pattern1 = rb'(function [\w$]+\(\)\{const t=)(\w+)(\.screen\.)getPrimaryDisplay\(\)'

    def replacement1_func(m):
        electron_var = m.group(2).decode('utf-8')
        return (m.group(1) + m.group(2) + m.group(3) +
                f'getDisplayNearestPoint({electron_var}.screen.getCursorScreenPoint())'.encode('utf-8'))

    content, count1 = re.subn(pattern1, replacement1_func, content)
    if count1 > 0:
        print(f"  [OK] position function: {count1} match(es)")
    else:
        print(f"  [FAIL] position function: 0 matches, expected >= 1")
        failed = True

    # Patch 2: In fallback display lookup
    # Pattern matches: VAR||(VAR=ELECTRON.screen.getPrimaryDisplay())
    # Variable name changes between versions (r, n, etc.), so use backreference
    pattern2 = rb'(\w)\|\|\(\1=(\w+)\.screen\.getPrimaryDisplay\(\)\)'

    def replacement2_func(m):
        var_name = m.group(1).decode('utf-8')
        electron_var = m.group(2).decode('utf-8')
        return f'{var_name}||({var_name}={electron_var}.screen.getDisplayNearestPoint({electron_var}.screen.getCursorScreenPoint()))'.encode('utf-8')

    content, count2 = re.subn(pattern2, replacement2_func, content)
    if count2 > 0:
        print(f"  [OK] fallback display: {count2} match(es)")
    else:
        print(f"  [FAIL] fallback display: 0 matches, expected >= 1")
        failed = True

    # Patch 3: Disabled - this optional enhancement caused syntax errors
    # The pattern only matched part of a function, leaving dangling code
    print(f"  [INFO] dTe() override: skipped (disabled)")

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
