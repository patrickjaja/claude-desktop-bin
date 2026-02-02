#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Patch Claude Desktop to use native window frames on Linux.

On Linux, titleBarStyle:"hidden" with frame defaulting to true causes Electron to
create an invisible drag region across the top of the window, intercepting mouse
events and making the top bar non-clickable. We:
1. Set frame:true explicitly for native window management
2. Replace titleBarStyle:"hidden" with "default" on Linux (main window only)

IMPORTANT: Quick Entry window needs frame:false + titleBarStyle:"hidden" for
transparency - we preserve that by targeting only the main window pattern.

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
        # No frame:!1 found outside Quick Entry - this is OK for newer versions
        # The main window now uses titleBarStyle:"hidden" without explicit frame:false
        print(f"  [INFO] No frame:!1 found outside Quick Entry (main window uses native frames by default)")

    # Step 4: Restore Quick Entry frame setting
    if has_quick_entry:
        content = content.replace(b'transparent:!0,' + marker, quick_entry_pattern)
        print(f"  [OK] Restored Quick Entry frame:!1 (transparent)")

    # Step 5: Replace titleBarStyle:"hidden" with platform-conditional for main window
    # The main window pattern includes titleBarOverlay nearby, distinguishing it from
    # Quick Entry. On Linux, titleBarStyle:"hidden" creates an invisible drag region
    # that blocks clicks on the top bar even when frame:true.
    main_titlebar_pattern = rb'titleBarStyle:"hidden",(titleBarOverlay:\w+)'
    def titlebar_replacement(m):
        overlay = m.group(1)
        return b'titleBarStyle:process.platform==="linux"?"default":"hidden",' + overlay

    content, count = re.subn(main_titlebar_pattern, titlebar_replacement, content)
    if count > 0:
        print(f"  [OK] titleBarStyle:\"hidden\" -> platform-conditional: {count} match(es)")
    else:
        # Check if already patched or pattern changed
        if b'titleBarStyle:process.platform==="linux"?"default":"hidden"' in content:
            print(f"  [INFO] titleBarStyle already patched")
        else:
            print(f"  [WARN] titleBarStyle:\"hidden\" pattern not found near titleBarOverlay")

    # Write back if changed
    if content != original_content:
        with open(filepath, 'wb') as f:
            f.write(content)
        print("  [PASS] Native frame patched successfully")
        return True
    else:
        print("  [PASS] No changes needed (main window already uses native frames)")
        return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_native_frame(sys.argv[1])
    sys.exit(0 if success else 1)
