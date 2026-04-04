#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Fix Quick Entry ready-to-show hang on Wayland.

Electron's 'ready-to-show' event never fires for transparent, frameless
BrowserWindows on native Wayland. The Quick Entry window (Mlr function)
awaits this event indefinitely, causing the overlay to never appear.

This patch adds a 200ms timeout to the ready-to-show wait so the Quick
Entry window proceeds to show even if the event never fires.

Usage: python3 fix_quick_entry_ready_wayland.py <path_to_index.js>
"""

import sys
import os


def patch_quick_entry_ready(filepath):
    """Add timeout to Quick Entry ready-to-show wait."""

    print("=== Patch: fix_quick_entry_ready_wayland ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, "rb") as f:
        content = f.read()

    original_content = content

    # The Mlr function waits for ready-to-show:
    #   NEe||await(nK==null?void 0:nK.catch(n=>{R.error("Quick Entry: Error waiting for ready %o",{error:n})}))
    # We wrap this in Promise.race with a 200ms timeout.
    old = b'NEe||await(nK==null?void 0:nK.catch(n=>{R.error("Quick Entry: Error waiting for ready %o",{error:n})}))'
    new = b'NEe||await Promise.race([nK==null?void 0:nK.catch(n=>{R.error("Quick Entry: Error waiting for ready %o",{error:n})}),new Promise(_r=>setTimeout(_r,200))])'

    if old in content:
        content = content.replace(old, new, 1)
        print("  [OK] ready-to-show timeout (200ms) added")
    else:
        print("  [FAIL] ready-to-show wait pattern not found")
        return False

    if content != original_content:
        with open(filepath, "wb") as f:
            f.write(content)
        print("  [PASS] Quick Entry ready-to-show timeout applied")
        return True
    else:
        print("  [WARN] No changes made")
        return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_quick_entry_ready(sys.argv[1])
    sys.exit(0 if success else 1)
