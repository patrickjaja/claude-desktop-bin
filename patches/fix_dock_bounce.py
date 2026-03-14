#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Disable dockBounceEnabled on Linux to prevent taskbar flashing.

On KDE Plasma 6 with Wayland, Chromium's xdg_activation_v1 handling causes
the taskbar to flash (demands-attention state) on every focus change. The
requestUserAttention() method calls BrowserWindow.flashFrame() when
dockBounceEnabled is true, which makes the problem worse. This patch
disables the feature flag check on Linux so flashFrame is never called.

The desktop notification itself is unaffected — only the taskbar flash
is suppressed.

See: https://github.com/patrickjaja/claude-desktop-bin/issues/10

Usage: python3 fix_dock_bounce.py <path_to_index.js>
"""

import sys
import os
import re


def patch_dock_bounce(filepath):
    """Disable dockBounceEnabled on Linux."""

    print(f"=== Patch: fix_dock_bounce ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content

    # Patch: wrap dockBounceEnabled check with a Linux platform guard
    # Original: Zr("dockBounceEnabled") (where Zr is minified feature flag getter)
    # Patched:  (process.platform!=="linux"&&Zr("dockBounceEnabled"))

    # Check if already patched first
    if b'process.platform!=="linux"&&' in content and b'"dockBounceEnabled"' in content:
        print(f"  [INFO] dockBounceEnabled already patched")
    else:
        pattern = rb'(\w+)\("dockBounceEnabled"\)'

        def replacement(m):
            fn = m.group(1)
            return b'(process.platform!=="linux"&&' + fn + b'("dockBounceEnabled"))'

        content, count = re.subn(pattern, replacement, content)

        if count > 0:
            print(f"  [OK] dockBounceEnabled Linux guard: {count} match(es)")
        else:
            print(f"  [FAIL] dockBounceEnabled pattern not found")
            return False

    # Write back if changed
    if content != original_content:
        with open(filepath, 'wb') as f:
            f.write(content)
        print("  [PASS] Dock bounce disabled on Linux")
        return True
    else:
        print("  [PASS] No changes needed (already patched)")
        return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_dock_bounce(sys.argv[1])
    sys.exit(0 if success else 1)
