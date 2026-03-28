#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Fix updater state missing `version` property on Linux.

On Linux, auto-update is disabled (no update URL for Linux), so the updater
state stays permanently at {status: "idle"} which has no `version` or
`versionNumber` property. The "ready" state includes both, and the web
frontend may call `.includes()` on `version` without null-checking, causing:

  TypeError: Cannot read properties of undefined (reading 'includes')

This patch adds `version:"",versionNumber:""` to the idle state return so
downstream code always has a defined string to work with.

Usage: python3 fix_updater_state_linux.py <path_to_index.js>
"""

import sys
import os
import re


def patch_updater_state(filepath):
    """Add version property to idle updater state."""

    print("=== Patch: fix_updater_state_linux ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, "rb") as f:
        content = f.read()

    # Pattern: case"idle":return{status:<var>.Idle}
    # We need to add version:"",versionNumber:"" before the closing brace.
    # Use [\w$]+ for minified variable names (JS identifiers may contain $).
    pattern = rb'(case"idle":return\{status:[\w$]+\.[\w$]+)\}'
    replacement = rb'\1,version:"",versionNumber:""}'

    # Check if already patched
    already = rb'case"idle":return\{status:[\w$]+\.[\w$]+,version:"",versionNumber:""\}'
    if re.search(already, content):
        print("  [OK] Updater idle state: already patched (skipped)")
        return True

    content_new, count = re.subn(pattern, replacement, content, count=1)
    if count >= 1:
        with open(filepath, "wb") as f:
            f.write(content_new)
        print(f"  [OK] Updater idle state: added version/versionNumber ({count} match)")
        return True
    else:
        print("  [WARN] Updater idle state: pattern not found (may have changed)")
        return True  # Non-critical, don't fail the build


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_updater_state(sys.argv[1])
    sys.exit(0 if success else 1)
