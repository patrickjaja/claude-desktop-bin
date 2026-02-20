#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Patch Claude Desktop to fix tray icon path on Linux.

On Linux, process.resourcesPath points to the Electron resources directory
(e.g., /usr/lib/electron/resources/) but our tray icons are installed to
a locales/ directory alongside app.asar. This patch redirects the tray icon
path lookup to use a runtime expression that works for any install method
(Arch package, Debian package, AppImage).

Usage: python3 fix_tray_path.py <path_to_index.js>
"""

import sys
import os
import re


def patch_tray_path(filepath):
    """Patch the tray icon resources path to use our package directory."""

    print(f"=== Patch: fix_tray_path ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content
    patches_applied = 0

    # Pattern 1: Generic function pattern with variable electron/process module names
    # Pattern: function FUNCNAME(){return ELECTRON.app.isPackaged?PROCESS.resourcesPath:...}
    # Variable names change between versions (ce->de, pn->gn, etc.)
    # Note: [\w$]+ is used because minified JS names can contain $ (e.g., f$t)
    pattern1 = rb'(function [\w$]+\(\)\{return )([\w$]+)(\.app\.isPackaged\?)([\w$]+)(\.resourcesPath)(:[^}]+\})'

    def replacement1_func(m):
        prefix = m.group(1)
        electron_var = m.group(2)
        middle = m.group(3)
        # Use runtime expression that resolves correctly for any install location
        return (prefix + electron_var + middle +
                b'(require("path").dirname(require("electron").app.getAppPath())+"/locales")' + m.group(6))

    content, count1 = re.subn(pattern1, replacement1_func, content)
    if count1 > 0:
        patches_applied += count1
        print(f"  [OK] generic resources path function: {count1} match(es)")

    # Pattern 2: Alternative pattern with process.resourcesPath directly (no variable)
    if patches_applied == 0:
        pattern2 = rb'(function [\w$]+\(\)\{return )([\w$]+)(\.app\.isPackaged\?)process\.resourcesPath(:[^}]+\})'

        def replacement2_func(m):
            prefix = m.group(1)
            electron_var = m.group(2)
            middle = m.group(3)
            suffix = m.group(4)
            # Use runtime expression that resolves correctly for any install location
            return (prefix + electron_var + middle +
                    b'(require("path").dirname(require("electron").app.getAppPath())+"/locales")' + suffix)

        content, count2 = re.subn(pattern2, replacement2_func, content)
        if count2 > 0:
            patches_applied += count2
            print(f"  [OK] process.resourcesPath function: {count2} match(es)")

    # Check results - at least one pattern must match
    if patches_applied == 0:
        print(f"  [FAIL] No patterns matched (tried 2 alternatives), expected >= 1")
        return False

    # Write back if changed
    if content != original_content:
        with open(filepath, 'wb') as f:
            f.write(content)
        print("  [PASS] Tray path patched successfully")
        return True
    else:
        print("  [WARN] No changes made (patterns may have already been applied)")
        return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_tray_path(sys.argv[1])
    sys.exit(0 if success else 1)
