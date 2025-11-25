#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Patch Claude Desktop to use native window frames on Linux.

On Linux/XFCE, frame:false doesn't work properly - the WM still adds decorations.
So we use frame:true for native window management, but also show Claude's internal
title bar for the hamburger menu and Claude icon.

IMPORTANT: Quick Entry window needs frame:false for transparency - we preserve that.

Usage: python3 fix_native_frame.py <path_to_index.js>
"""

import sys
import os
import re


def patch_native_frame(filepath):
    """Patch BrowserWindow to use native frames on Linux (main window only)."""

    print(f"Patching native frames in: {filepath}")

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content
    patches_applied = 0

    # Step 1: Temporarily mark the Quick Entry pattern (transparent windows need frame:false)
    marker = b'__QUICK_ENTRY_FRAME_PRESERVE__'
    content = re.sub(rb'transparent:!0,frame:!1', b'transparent:!0,' + marker, content)

    # Step 2: Replace frame:!1 (false) with frame:true for main window
    pattern = rb'frame\s*:\s*!1'
    replacement = b'frame:true'
    content, count = re.subn(pattern, replacement, content)
    if count > 0:
        patches_applied += count
        print(f"  Replaced frame:!1 -> frame:true: {count} occurrence(s)")

    # Step 3: Restore Quick Entry frame setting
    content = content.replace(marker, b'frame:!1')
    print(f"  Preserved frame:!1 for Quick Entry window (transparent)")

    if content != original_content:
        with open(filepath, 'wb') as f:
            f.write(content)
        print(f"Native frame patches applied: {patches_applied} total")
        return True
    else:
        print("No native frame patches needed")
        return False


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    filepath = sys.argv[1]
    if not os.path.exists(filepath):
        print(f"Error: File not found: {filepath}")
        sys.exit(1)

    patch_native_frame(filepath)
    # Always exit 0 - patch is best-effort
    sys.exit(0)
