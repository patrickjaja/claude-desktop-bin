#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Patch Claude Desktop Quick Entry to spawn on the monitor where the cursor is,
and to auto-focus the input field on Linux.

Patches:
1. Replace getPrimaryDisplay() with getDisplayNearestPoint(getCursorScreenPoint())
2. (Optional) Fallback display lookup
3. Override position-save/restore to always use cursor's display
4. On Linux/X11: setPosition BEFORE show() to prevent WM smart-placement race,
   and add focus() + webContents.focus() after show() for auto-focus

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

    # Patch 1: In position function - the Quick Entry centering function
    # Pattern matches: function FUNCNAME(){const t=ELECTRON.screen.getPrimaryDisplay()
    # Function names change between versions (pTe, lPe, kFt, etc.)
    # Electron var may contain $ (e.g. $e), so use [\w$]+
    pattern1 = rb'(function [\w$]+\(\)\{const [\w$]+=)([\w$]+)(\.screen\.)getPrimaryDisplay\(\)'

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

    # Patch 2 (optional): Fallback display lookup
    # Pattern: VAR||(VAR=ELECTRON.screen.getPrimaryDisplay())
    # This lazy-init pattern was removed in newer versions, so it's optional.
    pattern2 = rb'([\w$])\|\|\(\1=([\w$]+)\.screen\.getPrimaryDisplay\(\)\)'

    def replacement2_func(m):
        var_name = m.group(1).decode('utf-8')
        electron_var = m.group(2).decode('utf-8')
        return f'{var_name}||({var_name}={electron_var}.screen.getDisplayNearestPoint({electron_var}.screen.getCursorScreenPoint()))'.encode('utf-8')

    content, count2 = re.subn(pattern2, replacement2_func, content)
    if count2 > 0:
        print(f"  [OK] fallback display: {count2} match(es)")
    else:
        print(f"  [INFO] fallback display: 0 matches (pattern removed in this version, optional)")

    # Patch 3: Override position-restore function to always use cursor's display
    # In v1.1.7714+, T7t() saves/restores Quick Entry position per-monitor,
    # bypassing our cursor-based I7t() patch. We make it always delegate to
    # the centering function (now cursor-aware via Patch 1) by short-circuiting
    # the saved position check.
    # Pattern: function T7t(){const t=Ki.get("quickWindowPosition",null),...if(!(t&&t.absolute...))return I7t();
    # We replace the saved-position guard to always return the centering function.
    pattern3 = rb'(function [\w$]+\(\)\{const [\w$]+=[\w$]+\.get\("quickWindowPosition",null\),[\w$]+=[\w$]+\.screen\.getAllDisplays\(\);if\(!\()[\w$]+&&[\w$]+\.absolutePointInWorkspace&&[\w$]+\.monitor&&[\w$]+\.relativePointFromMonitor(\)\)return )([\w$]+)\(\)'

    def replacement3_func(m):
        # Replace condition with !1 (false), so !(!1) = !(false) = true → always returns centering fn
        return m.group(1) + b'!1' + m.group(2) + m.group(3) + b'()'

    content, count3 = re.subn(pattern3, replacement3_func, content)
    if count3 > 0:
        print(f"  [OK] position restore override: {count3} match(es)")
    else:
        print(f"  [INFO] position restore override: 0 matches (older version without saved position)")

    # Patch 4: Fix show/setPosition ordering and add focus on Linux
    # On macOS, type:"panel" auto-focuses and the WM respects position hints.
    # On Linux/X11, ai.show() triggers WM smart-placement (near focused window)
    # which overrides our position. Also, without type:"panel", no auto-focus.
    # Fix: setPosition before show (hint), show, focus, then setTimeout to
    # re-apply position AFTER the WM finishes its async placement, and focus
    # the webContents so the input field is ready for typing.
    # Pattern: ai.show()}return ai.setPosition(Math.round(VAR.x),Math.round(VAR.y)),!0}
    pattern4 = rb'ai\.show\(\)\}return ai\.setPosition\(Math\.round\(([\w$]+)\.x\),Math\.round\(\1\.y\)\),!0\}'

    def replacement4_func(m):
        v = m.group(1).decode('utf-8')
        return (
            f'ai.setPosition(Math.round({v}.x),Math.round({v}.y)),'
            f'ai.show(),'
            f'ai.focus(),'
            f'setTimeout(()=>{{ai.isDestroyed()||(ai.setPosition(Math.round({v}.x),Math.round({v}.y)),ai.webContents.focus())}},50)'
            f'}}return!0}}'
        ).encode('utf-8')

    content, count4 = re.subn(pattern4, replacement4_func, content)
    if count4 > 0:
        print(f"  [OK] show/focus ordering fix: {count4} match(es)")
    else:
        print(f"  [FAIL] show/focus ordering: 0 matches")
        failed = True

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
