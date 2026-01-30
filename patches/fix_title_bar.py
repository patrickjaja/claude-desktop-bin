#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Fix missing title bar on Linux by using the native window manager title bar.

The main window is created with titleBarStyle:"hidden", which tells Electron
to hide the native title bar. On macOS/Windows, a custom internal title bar
component renders inside the web content. On Linux with Electron 39's
WebContentsView architecture, the internal title bar (rendered in the parent
BrowserWindow's webContents) is occluded by child WebContentsViews and
never visible.

This patch changes titleBarStyle from "hidden" to "default" for the main
window only, letting the Linux window manager provide a native title bar.
The pattern is anchored by titleBarOverlay (only present on the main window)
to avoid affecting the Quick Entry window which also uses titleBarStyle:"hidden".

Usage: python3 fix_title_bar.py <path_to_index.js>
"""

import sys
import os
import re


def patch_title_bar(filepath):
    """Use native WM title bar on Linux by changing titleBarStyle from hidden to default."""

    print(f"=== Patch: fix_title_bar ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content

    # Pattern: titleBarStyle:"hidden",titleBarOverlay:XX
    # The titleBarOverlay anchor ensures we only match the main window,
    # not the Quick Entry window (which has skipTaskbar after titleBarStyle)
    pattern = rb'titleBarStyle:"hidden",(titleBarOverlay:\w+)'
    replacement = rb'titleBarStyle:"default",\1'

    content, count = re.subn(pattern, replacement, content, count=1)
    if count == 1:
        print(f'  [OK] Main window titleBarStyle: "hidden" → "default" ({count} match)')
    else:
        print(f"  [FAIL] titleBarStyle pattern: {count} matches, expected 1")
        return False

    if content != original_content:
        with open(filepath, 'wb') as f:
            f.write(content)
        print("  [PASS] Native title bar enabled for Linux")
        return True
    else:
        print("  [WARN] No changes made (pattern may have already been applied)")
        return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_title_bar(sys.argv[1])
    sys.exit(0 if success else 1)
