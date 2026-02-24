#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Fix MCP server reconnection error.

The connect-to-mcp-server IPC handler calls f.connect(h) on internal MCP
servers without first closing any existing transport. If the renderer
requests a reconnection (e.g., on page reload), the Protocol class throws
"Already connected to a transport" because _transport is still set.

Fix: call await f.close() before await f.connect(h) to clean up the
existing transport gracefully.

Usage: python3 fix_mcp_reconnect.py <path_to_index.js>
"""

import sys
import os
import re


def patch_mcp_reconnect(filepath):
    """Add close() before connect() in MCP server handler."""

    print(f"=== Patch: fix_mcp_reconnect ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, 'rb') as f:
        content = f.read()

    # The fix adds close() before connect() for internal MCP servers.
    #
    # In v1.1.4088+, the upstream already includes this fix:
    #   t.transport&&await t.close(),await t.connect(n)
    # Check for the upstream fix first.
    upstream_pattern = rb'[\w$]+\.transport&&await [\w$]+\.close\(\),await [\w$]+\.connect\([\w$]+\)'
    if re.search(upstream_pattern, content):
        print(f"  [OK] MCP reconnect: upstream already includes close-before-connect")
        print("  [PASS] No patch needed (fix is upstream)")
        return True

    # Fallback: try to patch the old pattern
    # Pattern: await VAR.connect(VAR) in internal server connect function
    pattern = rb'(const ([\w$]+)=[\w$]+\([\w$]+\);if\(\2\)\{[^}]*?)(await \2\.connect\(([\w$]+)\))'

    def replacement(m):
        return m.group(1) + b'await ' + m.group(2) + b'.close().catch(()=>{}),' + m.group(3)

    content_new, count = re.subn(pattern, replacement, content)

    if count >= 1:
        print(f"  [OK] MCP reconnect fix: {count} match(es)")
    else:
        print(f"  [FAIL] MCP reconnect: pattern not found")
        return False

    if content_new != content:
        with open(filepath, 'wb') as f:
            f.write(content_new)
        print("  [PASS] MCP reconnect patched successfully")
    else:
        print("  [WARN] No changes made")

    return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_mcp_reconnect(sys.argv[1])
    sys.exit(0 if success else 1)
