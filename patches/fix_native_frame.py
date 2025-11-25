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

    print(f"=== Patch: fix_native_frame ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content
    failed = False

    # Step 1: Check if transparent window pattern exists (Quick Entry)
    quick_entry_pattern = rb'transparent:!0,frame:!1'
    has_quick_entry = quick_entry_pattern in content
    if has_quick_entry:
        print(f"  [OK] Quick Entry pattern found (will preserve)")
    else:
        print(f"  [INFO] Quick Entry pattern not found (may be already patched)")

    # Step 2: Temporarily mark the Quick Entry pattern
    marker = b'__QUICK_ENTRY_FRAME_PRESERVE__'
    if has_quick_entry:
        content = content.replace(quick_entry_pattern, b'transparent:!0,' + marker)

    # Step 3: Replace frame:!1 (false) with frame:true for main window
    pattern = rb'frame\s*:\s*!1'
    replacement = b'frame:true'
    content, count = re.subn(pattern, replacement, content)
    if count > 0:
        print(f"  [OK] frame:!1 -> frame:true: {count} match(es)")
    else:
        print(f"  [FAIL] frame:!1: 0 matches, expected >= 1")
        failed = True

    # Step 4: Restore Quick Entry frame setting
    if has_quick_entry:
        content = content.replace(b'transparent:!0,' + marker, quick_entry_pattern)
        print(f"  [OK] Restored Quick Entry frame:!1 (transparent)")

    # Check results
    if failed:
        print("  [FAIL] Required patterns did not match")
        return False

    # Write back if changed
    if content != original_content:
        with open(filepath, 'wb') as f:
            f.write(content)
        print("  [PASS] Native frame patched successfully")
        return True
    else:
        print("  [WARN] No changes made (patterns may have already been applied)")
        return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_native_frame(sys.argv[1])
    sys.exit(0 if success else 1)
