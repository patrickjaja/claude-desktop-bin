#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Patch Claude Desktop locale file paths for Linux.

The official Claude Desktop expects locale files in Electron's resourcesPath,
but on Linux we need to redirect to our install location. Uses a runtime
expression based on app.getAppPath() so it works for any install method
(Arch package, Debian package, AppImage).

Usage: python3 fix_locale_paths.py <path_to_index.js>
"""

import sys
import os
import re


def patch_locale_paths(filepath):
    """Patch locale file paths to use Linux install location."""

    print("=== Patch: fix_locale_paths ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, "rb") as f:
        content = f.read()

    original_content = content
    failed = False

    # Replace process.resourcesPath with a runtime expression that resolves
    # correctly for any install location (Arch, Debian, AppImage)
    old_resource_path = b"process.resourcesPath"
    new_resource_path = b'(require("path").dirname(require("electron").app.getAppPath())+"/locales")'

    count1 = content.count(old_resource_path)
    if count1 >= 1:
        content = content.replace(old_resource_path, new_resource_path)
        print(f"  [OK] process.resourcesPath: {count1} match(es)")
    else:
        print("  [FAIL] process.resourcesPath: 0 matches, expected >= 1")
        failed = True

    # Also replace any hardcoded electron paths (optional - may not exist)
    pattern = rb"/usr/lib/electron\d+/resources"
    replacement = b'(require("path").dirname(require("electron").app.getAppPath())+"/locales")'
    content, count2 = re.subn(pattern, replacement, content)
    if count2 > 0:
        print(f"  [OK] hardcoded electron paths: {count2} match(es)")
    else:
        print("  [INFO] hardcoded electron paths: 0 matches (optional)")

    # Check results
    if failed:
        print("  [FAIL] Required patterns did not match")
        return False

    # Write back if changed
    if content != original_content:
        with open(filepath, "wb") as f:
            f.write(content)
        print("  [PASS] All required patterns matched and applied")
    else:
        print("  [WARN] No changes made (patterns may have already been applied)")

    # Also patch index.pre.js if it exists (new in v1.2278.0 — bootstrap file)
    pre_js = os.path.join(os.path.dirname(filepath), "index.pre.js")
    if os.path.exists(pre_js):
        with open(pre_js, "rb") as f:
            pre_content = f.read()
        pre_count = pre_content.count(old_resource_path)
        if pre_count > 0:
            pre_content = pre_content.replace(old_resource_path, new_resource_path)
            with open(pre_js, "wb") as f:
                f.write(pre_content)
            print(f"  [OK] index.pre.js: process.resourcesPath patched ({pre_count} match)")
        else:
            print("  [INFO] index.pre.js: no process.resourcesPath (already patched or absent)")

    return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_locale_paths(sys.argv[1])
    sys.exit(0 if success else 1)
