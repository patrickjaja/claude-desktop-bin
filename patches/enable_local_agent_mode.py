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
    """Enable Local Agent Mode (chillingSlothFeat) on Linux by patching qWe function."""

    print(f"=== Patch: enable_local_agent_mode ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content
    failed = False

    # Patch 1: Modify qWe() function (chillingSlothFeat)
    # Original: function qWe(){return process.platform!=="darwin"?{status:"unavailable"}:{status:"supported"}}
    # Changed:  function qWe(){return{status:"supported"}}
    #
    # Pattern matches the darwin-only check and replaces with always-supported
    pattern1 = rb'function qWe\(\)\{return process\.platform!=="darwin"\?\{status:"unavailable"\}:\{status:"supported"\}\}'
    replacement1 = b'function qWe(){return{status:"supported"}}'

    content, count1 = re.subn(pattern1, replacement1, content)
    if count1 > 0:
        print(f"  [OK] qWe (chillingSlothFeat): {count1} match(es)")
    else:
        # Try alternative pattern in case of slight variations
        pattern1_alt = rb'(function qWe\(\)\{return )process\.platform!=="darwin"\?\{status:"unavailable"\}:(\{status:"supported"\})\}'
        content, count1 = re.subn(pattern1_alt, rb'\1\2}', content)
        if count1 > 0:
            print(f"  [OK] qWe (chillingSlothFeat) alt: {count1} match(es)")
        else:
            print(f"  [FAIL] qWe (chillingSlothFeat): 0 matches, expected 1")
            failed = True

    # Patch 2: Modify zWe() function (quietPenguin)
    # This feature is also darwin-only but may be related to agent mode
    # Original: function zWe(){return process.platform!=="darwin"?{status:"unavailable"}:{status:"supported"}}
    # Changed:  function zWe(){return{status:"supported"}}
    pattern2 = rb'function zWe\(\)\{return process\.platform!=="darwin"\?\{status:"unavailable"\}:\{status:"supported"\}\}'
    replacement2 = b'function zWe(){return{status:"supported"}}'

    content, count2 = re.subn(pattern2, replacement2, content)
    if count2 > 0:
        print(f"  [OK] zWe (quietPenguin): {count2} match(es)")
    else:
        print(f"  [INFO] zWe (quietPenguin): 0 matches (may not exist in this version)")

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
