#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Enable the read_terminal MCP server on Linux.

The built-in read_terminal MCP server has a hardcoded darwin platform gate:

    isEnabled:t=>t.sessionType==="ccd"&&process.platform==="darwin"&&Qn("397125142")

This patch widens the gate to also accept Linux:

    isEnabled:t=>t.sessionType==="ccd"&&(process.platform==="darwin"||process.platform==="linux")&&Qn("397125142")

The feature flag function name (Qn) and ID (397125142) are minified/version-specific,
so the pattern uses \\w+ and \\d+ wildcards respectively.

Usage: python3 fix_read_terminal_linux.py <path_to_index.js>
"""

import sys
import os
import re


def patch_read_terminal_linux(filepath):
    """Enable read_terminal MCP server on Linux."""

    print(f"=== Patch: fix_read_terminal_linux ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content

    # Pattern: the isEnabled gate for read_terminal
    #
    # Original: isEnabled:t=>t.sessionType==="ccd"&&process.platform==="darwin"&&Qn("397125142")
    # Patched:  isEnabled:t=>t.sessionType==="ccd"&&(process.platform==="darwin"||process.platform==="linux")&&Qn("397125142")
    #
    # The feature flag function name (\w+) and ID (\d+) are version-specific.
    pattern = rb'(sessionType==="ccd"&&)process\.platform==="darwin"(&&\w+\("\d+"\))'

    def replacement(m):
        return (m.group(1) +
                b'(process.platform==="darwin"||process.platform==="linux")' +
                m.group(2))

    content, count = re.subn(pattern, replacement, content)
    if count > 0:
        print(f"  [OK] read_terminal isEnabled: {count} match(es)")
    else:
        print(f"  [FAIL] read_terminal isEnabled: 0 matches")
        return False

    # Write back if changed
    if content != original_content:
        with open(filepath, 'wb') as f:
            f.write(content)
        print("  [PASS] read_terminal enabled on Linux")
        return True
    else:
        print("  [WARN] No changes made")
        return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_read_terminal_linux(sys.argv[1])
    sys.exit(0 if success else 1)
