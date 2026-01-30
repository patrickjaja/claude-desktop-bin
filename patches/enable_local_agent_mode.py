#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Enable Local Agent Mode and Code features on Linux.

Three-part patch:
1. Individual function patches: Remove platform!=="darwin" gates from
   chillingSlothFeat and quietPenguin functions in Oh() (static layer).
2. mC() merger patch: Override QL()-blocked features at the async merger
   layer by appending quietPenguin, louderPenguin, and chillingSlothFeat
   with {status:"supported"} after the spread of Oh().
3. Preferences defaults patch: Change louderPenguinEnabled and
   quietPenguinEnabled defaults from false to true so the renderer
   (claude.ai web content) enables the Code tab UI.

The mC() patch makes features "supported" (capability), but the renderer
also checks the "Enabled" preference (user setting). Both must be true
for the Code tab to appear.

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

    # Patch 2: Override QL()-blocked features in mC() async merger
    # The mC() function merges Oh() with async overrides. Features wrapped by QL()
    # in Oh() are blocked in production. We append overrides after the last async
    # property so they take precedence over the ...Oh() spread.
    #
    # Before: yukonSilverGems:await XXX()})
    # After:  yukonSilverGems:await XXX(),quietPenguin:{status:"supported"},louderPenguin:{status:"supported"},chillingSlothFeat:{status:"supported"}})
    pattern2 = rb'(yukonSilverGems:await \w+\(\))\}\)'
    replacement2 = rb'\1,quietPenguin:{status:"supported"},louderPenguin:{status:"supported"},chillingSlothFeat:{status:"supported"}})'

    content, count2 = re.subn(pattern2, replacement2, content)
    if count2 >= 1:
        print(f"  [OK] mC() feature merger: 3 Code features overridden ({count2} match)")
    else:
        print(f"  [FAIL] mC() feature merger: 0 matches, expected 1")
        failed = True

    # Check results
    if failed:
        print("  [FAIL] Required patterns did not match")
        return False

    # Patch 3: Change preferences defaults for Code features
    # The renderer (claude.ai web content) checks louderPenguinEnabled and
    # quietPenguinEnabled preferences to show the Code tab. The defaults are
    # false (disabled). We change them to true so the Code tab appears.
    # Feature name strings are stable IPC identifiers (not minified).
    pattern3a = rb'quietPenguinEnabled:!1,louderPenguinEnabled:!1'
    replacement3a = rb'quietPenguinEnabled:!0,louderPenguinEnabled:!0'
    content, count3a = re.subn(pattern3a, replacement3a, content)
    if count3a >= 1:
        print(f"  [OK] Preferences defaults: quietPenguinEnabled + louderPenguinEnabled → true ({count3a} match)")
    else:
        print(f"  [FAIL] Preferences defaults: 0 matches for quietPenguinEnabled/louderPenguinEnabled")
        failed = True

    # Check results
    if failed:
        print("  [FAIL] Required patterns did not match")
        return False

    # Write back if changed
    if content != original_content:
        with open(filepath, 'wb') as f:
            f.write(content)
        print("  [PASS] Local Agent Mode and Code features enabled successfully")
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
