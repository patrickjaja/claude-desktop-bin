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

    print(f"Patching title bar in: {filepath}")

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content

    # Fix: if(!B&&e) -> if(B&&e) - removes the negation
    # This makes Linux show the internal title bar like Windows does
    pattern = rb'if\(!([a-zA-Z_][a-zA-Z0-9_]*)\s*&&\s*([a-zA-Z_][a-zA-Z0-9_]*)\)'
    replacement = rb'if(\1&&\2)'

    content, count = re.subn(pattern, replacement, content)

    if content != original_content:
        with open(filepath, 'wb') as f:
            f.write(content)
        print(f"Title bar patch applied: {count} replacement(s)")
        return True
    else:
        print("Warning: No title bar patterns found to patch")
        return False


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_MainWindowPage-*.js>")
        sys.exit(1)

    filepath = sys.argv[1]
    if not os.path.exists(filepath):
        print(f"Error: File not found: {filepath}")
        sys.exit(1)

    patch_title_bar(filepath)
    sys.exit(0)
