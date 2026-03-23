#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/mainView.js
# @patch-type: python
"""
Fix process.argv being undefined in the web renderer.

The preload exposes a filtered process object to the main world with only
arch, platform, type, and versions. The Claude Code SDK web bundle
(c30db9bec-CFBoXRyN.js) calls process.argv.includes("--debug") during
Vr.streamInput(), which throws:

  TypeError: Cannot read properties of undefined (reading 'includes')

This prevents Dispatch responses from rendering in the UI.

Fix: Add argv as an empty array to the exposed process object, right after
the platform spoof. The empty array makes .includes() return false (correct
behavior — the renderer is not in debug mode).

Usage: python3 fix_process_argv_renderer.py <path_to_mainView.js>
"""

import sys
import os
import re


def patch_process_argv(filepath):
    """Add process.argv to the exposed process object in the preload."""

    print(f"=== Patch: fix_process_argv_renderer ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, 'rb') as f:
        content = f.read()

    # Check if already patched
    if b'Ie.argv=[]' in content or b'Ie.argv = []' in content:
        print(f"  [OK] process.argv: already patched (skipped)")
        return True

    # Pattern: after the platform spoof, before exposeInMainWorld
    # Current: if(process.platform==="linux"){Ie.platform="win32"}
    # We insert Ie.argv=[] right after the closing brace of the platform check.
    #
    # Match the platform spoof block (may or may not be present depending on
    # whether enable_local_agent_mode.py ran first).
    # Strategy: find `Ie.platform="win32"}` and append after it, OR
    # find `Ie.version=` line and insert after `Ie.version=...;`

    # Try after platform spoof first
    marker = b'Ie.platform="win32"}'
    if marker in content:
        content = content.replace(marker, marker + b'Ie.argv=[];', 1)
        with open(filepath, 'wb') as f:
            f.write(content)
        print(f"  [OK] process.argv: added empty array (after platform spoof)")
        return True

    # Fallback: insert after Ie.version=...;
    # Pattern: Ie.version=<something>.appVersion;
    version_pattern = rb'(Ie\.version=\w+\(\)\.appVersion;)'
    match = re.search(version_pattern, content)
    if match:
        insert_point = match.end()
        content = content[:insert_point] + b'Ie.argv=[];' + content[insert_point:]
        with open(filepath, 'wb') as f:
            f.write(content)
        print(f"  [OK] process.argv: added empty array (after version)")
        return True

    print(f"  [FAIL] process.argv: could not find insertion point")
    return False


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_mainView.js>")
        sys.exit(1)

    success = patch_process_argv(sys.argv[1])
    sys.exit(0 if success else 1)
