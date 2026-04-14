#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/mainView.js
# @patch-type: python
"""
Inject a click interceptor for computer:// links in the renderer preload.

The claude.ai web app handles computer:// link clicks entirely in its React
code without triggering Electron navigation events (will-navigate,
setWindowOpenHandler). On macOS, the OS natively handles computer:// via a
registered URL scheme. On Linux, the click silently does nothing.

Fix: Add a document-level click handler (capture phase) in the preload that
intercepts clicks on <a href="computer://..."> elements and opens the file
using shell.openExternal with a file:// URL.

Usage: python3 fix_computer_url_renderer.py <path_to_mainView.js>
"""

import sys
import os


EXPECTED_PATCHES = 1


def patch_computer_url_renderer(filepath):
    """Inject computer:// click interceptor in the renderer preload."""

    print("=== Patch: fix_computer_url_renderer ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, "rb") as f:
        content = f.read()

    original_content = content
    patches_applied = 0

    marker = b"computer://__click_interceptor"

    if marker in content:
        print("  [OK] computer:// click interceptor: already patched")
        patches_applied += 1
    else:
        # Inject at the end of the preload, before the final closing.
        # The preload has `const r=require("electron")` at the top.
        # We use r.shell.openExternal to open the file.
        #
        # The click handler:
        # 1. Captures click events in capture phase (runs before React handlers)
        # 2. Finds the nearest <a> with href starting with "computer://"
        # 3. Converts computer:// to file:// and opens with shell.openExternal
        # 4. Prevents the default behavior and stops propagation

        interceptor = (
            b"\n/* computer://__click_interceptor */\n"
            b'document.addEventListener("click",function(e){'
            b"var a=e.target;"
            b'while(a&&a.tagName!=="A")a=a.parentElement;'
            b"if(!a||!a.href)return;"
            b'if(a.href.startsWith("computer://")){'
            b"e.preventDefault();e.stopPropagation();"
            b'var u=a.href.replace(/^computer:\\/\\/\\/?/,"file:///");'
            b'r.ipcRenderer.send("__open_computer_url",u)'
            b"}"
            b"},!0);\n"
        )

        # Append at the very end of the file
        content = content + interceptor
        print("  [OK] computer:// click interceptor: injected")
        patches_applied += 1

    if patches_applied < EXPECTED_PATCHES:
        print(f"  [FAIL] Only {patches_applied}/{EXPECTED_PATCHES} patches applied")
        return False

    if content != original_content:
        with open(filepath, "wb") as f:
            f.write(content)
        print("  [PASS] Click interceptor patched successfully")
    else:
        print("  [PASS] No changes needed (already patched)")

    return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_mainView.js>")
        sys.exit(1)

    success = patch_computer_url_renderer(sys.argv[1])
    sys.exit(0 if success else 1)
