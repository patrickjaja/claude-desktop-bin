#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Patch Claude Desktop to fix paths that use process.resourcesPath + "app.asar" on Linux.

Two fixes applied here (both must run BEFORE fix_locale_paths.py's global replace):

1. nodeHostPath — The MCP node host path uses process.resourcesPath in the packaged
   branch of a ternary. We replace the entire ternary with app.getAppPath().

2. shellPathWorker — The shell path worker function joins process.resourcesPath
   with "app.asar" to locate shellPathWorker.js. After fix_locale_paths.py runs,
   process.resourcesPath gets redirected to the locales directory, breaking this path.
   We replace process.resourcesPath,"app.asar" with app.getAppPath().

This patch is named fix_0_node_host.py so it runs BEFORE fix_locale_paths.py
(patches run in alphabetical order) and can match the original process.resourcesPath.

Usage: python3 fix_0_node_host.py <path_to_index.js>
"""

import sys
import os
import re


def patch_node_host(filepath):
    """Patch the MCP node host path to use app.getAppPath()."""

    print("=== Patch: fix_0_node_host ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, "rb") as f:
        content = f.read()

    original_content = content

    # Pattern matches the ORIGINAL nodeHostPath assignment (before any other patches)
    # It captures:
    #   Group 1: electron module variable (de, ce, etc.)
    #   Group 2: path module variable ($e, etc.) - note [\w$]+ to match $
    pattern = rb'this\.nodeHostPath=([\w$]+)\.app\.isPackaged\?([\w$]+)\.join\(process\.resourcesPath,"app\.asar","\.vite","build","mcp-runtime","nodeHost\.js"\):\2\.join\(\1\.app\.getAppPath\(\),"\.vite","build","mcp-runtime","nodeHost\.js"\)'

    def replacement(m):
        electron_var = m.group(1)
        path_var = m.group(2)
        # Use getAppPath() unconditionally - it returns the correct path on Linux
        return b"this.nodeHostPath=" + path_var + b".join(" + electron_var + b'.app.getAppPath(),".vite","build","mcp-runtime","nodeHost.js")'

    content, count = re.subn(pattern, replacement, content)

    if count > 0:
        print(f"  [OK] nodeHostPath: {count} match(es)")
    else:
        print("  [FAIL] nodeHostPath: 0 matches, expected 1")
        print("  This patch must run BEFORE fix_locale_paths.py (on original code)")
        return False

    # Shell Path Worker fix — same issue as nodeHost
    # Original: function QSt(){return Ae.join(process.resourcesPath,"app.asar",".vite","build","shell-path-worker","shellPathWorker.js")}
    # Fix: replace process.resourcesPath,"app.asar" with app.getAppPath()
    shell_pattern = rb'(function [\w$]+\(\)\{return )([\w$]+)(\.join\()process\.resourcesPath,"app\.asar",("\.vite","build","shell-path-worker","shellPathWorker\.js"\))'

    def shell_replacement(m):
        return m.group(1) + m.group(2) + m.group(3) + b'require("electron").app.getAppPath(),' + m.group(4)

    content, shell_count = re.subn(shell_pattern, shell_replacement, content)
    if shell_count > 0:
        print(f"  [OK] shellPathWorker: {shell_count} match(es)")
    else:
        print("  [WARN] shellPathWorker: 0 matches (pattern may have changed)")

    # Write back if changed
    if content != original_content:
        with open(filepath, "wb") as f:
            f.write(content)
        print("  [PASS] Node host path patched successfully")
        return True
    else:
        print("  [WARN] No changes made")
        return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_node_host(sys.argv[1])
    sys.exit(0 if success else 1)
