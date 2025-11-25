#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Patch Claude Desktop locale file paths for Linux.

The official Claude Desktop expects locale files in Electron's resourcesPath,
but on Linux with system Electron, we need to redirect to our install location.

Usage: python3 fix_locale_paths.py <path_to_index.js>
"""

import sys
import os
import re


def patch_locale_paths(filepath):
    """Patch locale file paths to use Linux install location."""

    print(f"=== Patch: fix_locale_paths ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content
    failed = False

    # Replace process.resourcesPath with our locale path
    old_resource_path = b'process.resourcesPath'
    new_resource_path = b'"/usr/lib/claude-desktop-bin/locales"'

    count1 = content.count(old_resource_path)
    if count1 >= 1:
        content = content.replace(old_resource_path, new_resource_path)
        print(f"  [OK] process.resourcesPath: {count1} match(es)")
    else:
        print(f"  [FAIL] process.resourcesPath: 0 matches, expected >= 1")
        failed = True

    # Also replace any hardcoded electron paths (optional - may not exist)
    pattern = rb'/usr/lib/electron\d+/resources'
    replacement = b'/usr/lib/claude-desktop-bin/locales'
    content, count2 = re.subn(pattern, replacement, content)
    if count2 > 0:
        print(f"  [OK] hardcoded electron paths: {count2} match(es)")
    else:
        print(f"  [INFO] hardcoded electron paths: 0 matches (optional)")

    # Check results
    if failed:
        print("  [FAIL] Required patterns did not match")
        return False

    # Write back if changed
    if content != original_content:
        with open(filepath, 'wb') as f:
            f.write(content)
        print("  [PASS] All required patterns matched and applied")
        return True
    else:
        print("  [WARN] No changes made (patterns may have already been applied)")
        return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_locale_paths(sys.argv[1])
    sys.exit(0 if success else 1)
