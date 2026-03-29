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

    print("=== Patch: fix_process_argv_renderer ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, "rb") as f:
        content = f.read()

    # Check if already patched (use flexible pattern for any variable name)
    if re.search(rb"\w+\.argv=\[\]", content):
        print("  [OK] process.argv: already patched (skipped)")
        return True

    # Pattern: after the platform spoof, before exposeInMainWorld
    # Current: if(process.platform==="linux"){<var>.platform="win32"}
    # We insert <var>.argv=[] right after the closing brace of the platform check.
    #
    # Use \w+ wildcards for the variable name since minified names change
    # between upstream releases (e.g., Ie -> at).

    # Primary: insert <var>.argv=[] just before exposeInMainWorld("process",<var>)
    expose_pattern = rb'(\w+\.contextBridge\.exposeInMainWorld\("process",)(\w+)(\))'
    match = re.search(expose_pattern, content)
    if match:
        var_name = match.group(2)
        insert = var_name + b".argv=[];"
        content = content[: match.start()] + insert + content[match.start() :]
        with open(filepath, "wb") as f:
            f.write(content)
        print(f"  [OK] process.argv: added {var_name.decode()}.argv=[] (before exposeInMainWorld)")
        return True

    # Fallback 1: after platform spoof
    spoof_pattern = rb'(\w+)(\.platform="win32"\})'
    match = re.search(spoof_pattern, content)
    if match:
        var_name = match.group(1)
        insert = var_name + b".argv=[];"
        content = content[: match.end()] + insert + content[match.end() :]
        with open(filepath, "wb") as f:
            f.write(content)
        print(f"  [OK] process.argv: added {var_name.decode()}.argv=[] (after platform spoof)")
        return True

    # Fallback 2: after <var>.version=...appVersion;
    version_pattern = rb"(\w+)(\.version=\w+\(\)\.appVersion;)"
    match = re.search(version_pattern, content)
    if match:
        var_name = match.group(1)
        insert = var_name + b".argv=[];"
        content = content[: match.end()] + insert + content[match.end() :]
        with open(filepath, "wb") as f:
            f.write(content)
        print(f"  [OK] process.argv: added {var_name.decode()}.argv=[] (after version)")
        return True

    print("  [FAIL] process.argv: could not find insertion point")
    return False


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_mainView.js>")
        sys.exit(1)

    success = patch_process_argv(sys.argv[1])
    sys.exit(0 if success else 1)
