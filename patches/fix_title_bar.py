#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/renderer/main_window/assets/MainWindowPage-*.js
# @patch-type: python
"""
Patch Claude Desktop to show internal title bar on Linux.

The original code has: if(!B&&e)return null
Where B = process.platform==="win32" (true on Windows)

Original behavior:
- Windows: !true=false, condition fails → title bar SHOWS
- Linux: !false=true, condition true → returns null → title bar HIDDEN

This patch changes: if(!B&&e) -> if(B&&e)
New behavior:
- Windows: true&&e=true → returns null → title bar hidden (uses native)
- Linux: false&&e=false → condition fails → title bar SHOWS

This gives Linux the same internal title bar that Windows has.

Usage: python3 fix_title_bar.py <path_to_MainWindowPage-*.js>
"""

import sys
import os
import re


def patch_title_bar(filepath):
    """Patch the title bar detection to show on Linux."""

    print(f"=== Patch: fix_title_bar ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content

    # Fix: if(!B&&e) -> if(B&&e) - removes the negation
    pattern = rb'if\(!([a-zA-Z_][a-zA-Z0-9_]*)\s*&&\s*([a-zA-Z_][a-zA-Z0-9_]*)\)'
    replacement = rb'if(\1&&\2)'

    content, count = re.subn(pattern, replacement, content)

    if count >= 1:
        print(f"  [OK] title bar condition: {count} match(es)")
    else:
        print(f"  [FAIL] title bar condition: 0 matches, expected >= 1")
        return False

    # Write back if changed
    if content != original_content:
        with open(filepath, 'wb') as f:
            f.write(content)
        print("  [PASS] Title bar patched successfully")
        return True
    else:
        print("  [WARN] No changes made (patterns may have already been applied)")
        return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_MainWindowPage-*.js>")
        sys.exit(1)

    success = patch_title_bar(sys.argv[1])
    sys.exit(0 if success else 1)
