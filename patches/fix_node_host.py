#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Patch Claude Desktop to fix MCP node host path on Linux.

The fix_locale_paths.py patch replaces process.resourcesPath with our locale path,
but this breaks the MCP node host path construction. This patch fixes it by
using app.getAppPath() which correctly points to the app.asar location.

Usage: python3 fix_node_host.py <path_to_index.js>
"""

import sys
import os
import re


def patch_node_host(filepath):
    """Patch the MCP node host path to use app.getAppPath()."""

    print(f"=== Patch: fix_node_host ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content

    # Pattern matches the nodeHostPath assignment after fix_locale_paths.py has run
    # It captures:
    #   Group 1: electron module variable (de, ce, etc.)
    #   Group 2: path module variable ($e, etc.) - note [\w$]+ to match $
    pattern = rb'this\.nodeHostPath=([\w$]+)\.app\.isPackaged\?([\w$]+)\.join\("/usr/lib/claude-desktop-bin/locales","app\.asar","\.vite","build","mcp-runtime","nodeHost\.js"\):\2\.join\(\1\.app\.getAppPath\(\),"\.vite","build","mcp-runtime","nodeHost\.js"\)'

    def replacement(m):
        electron_var = m.group(1)
        path_var = m.group(2)
        # Use getAppPath() unconditionally - it returns the correct path on Linux
        return b'this.nodeHostPath=' + path_var + b'.join(' + electron_var + b'.app.getAppPath(),".vite","build","mcp-runtime","nodeHost.js")'

    content, count = re.subn(pattern, replacement, content)

    if count > 0:
        print(f"  [OK] nodeHostPath: {count} match(es)")
    else:
        print(f"  [FAIL] nodeHostPath: 0 matches, expected 1")
        print(f"  This patch must run AFTER fix_locale_paths.py")
        return False

    # Write back if changed
    if content != original_content:
        with open(filepath, 'wb') as f:
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
