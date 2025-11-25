#!/usr/bin/env python3
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

    print(f"Patching locale paths in: {filepath}")

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content
    patches_applied = 0

    # Replace process.resourcesPath with our locale path
    old_resource_path = b'process.resourcesPath'
    new_resource_path = b'"/usr/lib/claude-desktop-bin/locales"'

    if old_resource_path in content:
        count = content.count(old_resource_path)
        content = content.replace(old_resource_path, new_resource_path)
        patches_applied += count
        print(f"  Replaced process.resourcesPath: {count} occurrence(s)")

    # Also replace any hardcoded electron paths
    pattern = rb'/usr/lib/electron\d+/resources'
    replacement = b'/usr/lib/claude-desktop-bin/locales'
    content, count = re.subn(pattern, replacement, content)
    if count > 0:
        patches_applied += count
        print(f"  Replaced hardcoded electron paths: {count} occurrence(s)")

    if content != original_content:
        with open(filepath, 'wb') as f:
            f.write(content)
        print(f"Locale path patches applied: {patches_applied} total")
        return True
    else:
        print("Warning: No locale path changes made")
        return False


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    filepath = sys.argv[1]
    if not os.path.exists(filepath):
        print(f"Error: File not found: {filepath}")
        sys.exit(1)

    success = patch_locale_paths(filepath)
    sys.exit(0 if success else 1)
