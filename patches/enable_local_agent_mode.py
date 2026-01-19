#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Enable Local Agent Mode (chillingSlothFeat) on Linux.

The original code gates this feature with `process.platform!=="darwin"` check,
returning {status:"unavailable"} on Linux. This patch removes that check to
enable the Local Agent Mode feature (Claude Code for Desktop with git worktrees).

This feature provides:
- Local agent sessions with isolated git worktrees
- Claude Code integration in Desktop app
- MCP server support for agent sessions
- PTY terminal support

NOTE: This does NOT enable:
- yukonSilver/SecureVM (requires @ant/claude-swift macOS native module)
- Echo/Screen capture (requires @ant/claude-swift macOS native module)
- Native Quick Entry (requires macOS-specific Swift code)

Usage: python3 enable_local_agent_mode.py <path_to_index.js>
"""

import sys
import os
import re


def patch_local_agent_mode(filepath):
    """Enable Local Agent Mode (chillingSlothFeat) on Linux by patching platform-gated functions."""

    print(f"=== Patch: enable_local_agent_mode ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content
    failed = False

    # Patch 1: Modify chillingSlothFeat function (variable name changes between versions)
    # Original: function XXX(){return process.platform!=="darwin"?{status:"unavailable"}:{status:"supported"}}
    # Changed:  function XXX(){return{status:"supported"}}
    #
    # Use flexible pattern with \w+ to match any minified function name
    # Known names: qWe (v1.0.x), wYe (v1.1.381)
    pattern1 = rb'(function )(\w+)(\(\)\{return )process\.platform!=="darwin"\?\{status:"unavailable"\}:(\{status:"supported"\}\})'

    def replacement1(m):
        func_name = m.group(2).decode('utf-8')
        return m.group(1) + m.group(2) + m.group(3) + m.group(4)

    # Count matches first to identify which function is chillingSlothFeat
    matches = list(re.finditer(pattern1, content))
    if len(matches) >= 1:
        # Replace all darwin-gated functions with always-supported
        content, count1 = re.subn(pattern1, replacement1, content)
        func_names = [m.group(2).decode('utf-8') for m in matches]
        print(f"  [OK] chillingSlothFeat ({func_names[0]}): 1 match")
        if len(matches) >= 2:
            print(f"  [OK] quietPenguin ({func_names[1]}): 1 match")
    else:
        print(f"  [FAIL] chillingSlothFeat: 0 matches, expected at least 1")
        failed = True

    # Check results
    if failed:
        print("  [FAIL] Required patterns did not match")
        return False

    # Write back if changed
    if content != original_content:
        with open(filepath, 'wb') as f:
            f.write(content)
        print("  [PASS] Local Agent Mode enabled successfully")
        return True
    else:
        print("  [WARN] No changes made (patterns may have already been applied)")
        return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_local_agent_mode(sys.argv[1])
    sys.exit(0 if success else 1)
