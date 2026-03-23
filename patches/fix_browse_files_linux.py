#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Enable directory browsing in the browseFiles dialog on Linux.

The upstream code only includes "openDirectory" in the Electron dialog properties
when running on macOS (darwin). On Linux, the dialog is limited to "openFile" +
"multiSelections", which prevents users from selecting directories.

Electron fully supports "openDirectory" on Linux, so we add a
process.platform==="linux" check alongside the existing darwin check.

Before:
  process.platform==="darwin"?["openFile","openDirectory","multiSelections"]:["openFile","multiSelections"]
After:
  process.platform==="darwin"||process.platform==="linux"?["openFile","openDirectory","multiSelections"]:["openFile","multiSelections"]

Usage: python3 fix_browse_files_linux.py <path_to_index.js>
"""

import sys
import os
import re


def patch_browse_files(filepath):
    """Enable directory browsing in the browseFiles dialog on Linux."""

    print(f"=== Patch: fix_browse_files_linux ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content

    # Pattern: the ternary that gates openDirectory behind darwin-only
    #
    # Original: process.platform==="darwin"?["openFile","openDirectory","multiSelections"]:["openFile","multiSelections"]
    # Patched:  process.platform==="darwin"||process.platform==="linux"?["openFile","openDirectory","multiSelections"]:["openFile","multiSelections"]
    #
    # All tokens here are stable Electron/Node API names (no minified variables).
    pattern = rb'process\.platform==="darwin"\?\["openFile","openDirectory","multiSelections"\]:\["openFile","multiSelections"\]'
    replacement = b'process.platform==="darwin"||process.platform==="linux"?["openFile","openDirectory","multiSelections"]:["openFile","multiSelections"]'

    content, count = re.subn(pattern, replacement, content)
    if count > 0:
        print(f"  [OK] browseFiles openDirectory: {count} match(es)")
    else:
        print(f"  [FAIL] browseFiles openDirectory: 0 matches")
        return False

    # Write back if changed
    if content != original_content:
        with open(filepath, 'wb') as f:
            f.write(content)
        print("  [PASS] Browse files dialog patched successfully")
        return True
    else:
        print("  [WARN] No changes made")
        return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_browse_files(sys.argv[1])
    sys.exit(0 if success else 1)
