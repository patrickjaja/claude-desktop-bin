#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Patch Claude Desktop to fix tray icon path on Linux.

On Linux, process.resourcesPath points to the Electron resources directory
(e.g., /usr/lib/electron/resources/) but our tray icons are installed to
/usr/lib/claude-desktop-bin/locales/. This patch redirects the tray icon
path lookup to use our package's directory.

The wTe() function is used to get the resources path for tray icons.
We patch it to return our locales directory on Linux.

Usage: python3 fix_tray_path.py <path_to_index.js>
"""

import sys
import os
import re


def patch_tray_path(filepath):
    """Patch the tray icon resources path to use our package directory."""

    print(f"Patching tray icon path in: {filepath}")

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content
    patches_applied = 0

    # Find the wTe function that returns the resources path
    # Pattern: function wTe(){return ce.app.isPackaged?pn.resourcesPath:$e.resolve(__dirname,"..","..","resources")}
    # We need to make it return our locales directory instead of process.resourcesPath

    # Look for the pattern: ce.app.isPackaged?pn.resourcesPath:
    # and replace pn.resourcesPath with our hardcoded path
    pattern = rb'(function \w+\(\)\{return ce\.app\.isPackaged\?)pn\.resourcesPath(:[^}]+\})'

    # Replace with a path that checks for Linux and returns our locales path
    # On Linux: /usr/lib/claude-desktop-bin/locales
    # Otherwise: use original pn.resourcesPath
    replacement = rb'\1(pn.platform==="linux"?"/usr/lib/claude-desktop-bin/locales":pn.resourcesPath)\2'

    content, count = re.subn(pattern, replacement, content)
    if count > 0:
        patches_applied += count
        print(f"  Patched resources path function: {count} occurrence(s)")

    # Alternative pattern - sometimes the function name is obfuscated differently
    # Try a more specific pattern for wTe
    if patches_applied == 0:
        pattern2 = rb'function wTe\(\)\{return ce\.app\.isPackaged\?pn\.resourcesPath:'
        replacement2 = rb'function wTe(){return ce.app.isPackaged?(pn.platform==="linux"?"/usr/lib/claude-desktop-bin/locales":pn.resourcesPath):'

        content, count2 = re.subn(pattern2, replacement2, content)
        if count2 > 0:
            patches_applied += count2
            print(f"  Patched wTe function directly: {count2} occurrence(s)")

    if content != original_content:
        with open(filepath, 'wb') as f:
            f.write(content)
        print(f"Tray path patches applied: {patches_applied} total")
        return True
    else:
        print("Warning: No tray path patches applied")
        return False


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    filepath = sys.argv[1]
    if not os.path.exists(filepath):
        print(f"Error: File not found: {filepath}")
        sys.exit(1)

    patch_tray_path(filepath)
    # Always exit 0 - patch is best-effort
    sys.exit(0)
