#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Enable Code features on Linux.

Four-part patch:
1. Individual function patch: Remove platform!=="darwin" gate from the
   quietPenguin function in Oh() (static layer). The chillingSlothFeat
   (Cowork/Local Agent Mode) function is intentionally left gated because
   it requires ClaudeVM which is not available on Linux.
2. Gate chillingSlothLocal on Linux: Add a Linux platform check so
   it returns {status:"unavailable"}. Without this, the web app shows the
   Cowork tab button (which hangs on infinite loading).
3. mC() merger patch: Override features at the async merger layer.
   Enables quietPenguin/louderPenguin with {status:"supported"} (bypasses
   QL gate), and explicitly disables all chillingSloth* features with
   {status:"unavailable"} to prevent the Cowork tab from appearing.
4. Preferences defaults patch: Change louderPenguinEnabled and
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
    """Enable Code features (quietPenguin/louderPenguin) on Linux by patching platform-gated functions."""

    print(f"=== Patch: enable_local_agent_mode ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content
    failed = False

    # Patch 1: Remove platform!=="darwin" gate from quietPenguin function only
    # Original: function XXX(){return process.platform!=="darwin"?{status:"unavailable"}:{status:"supported"}}
    # Changed:  function XXX(){return{status:"supported"}}
    #
    # Two functions match this pattern:
    #   matches[0] = chillingSlothFeat (e.g. agt) — SKIP (requires ClaudeVM, not available on Linux)
    #   matches[1] = quietPenguin (e.g. ogt) — PATCH
    #
    # Use flexible pattern with \w+ to match any minified function name
    pattern1 = rb'(function )(\w+)(\(\)\{return )process\.platform!=="darwin"\?\{status:"unavailable"\}:(\{status:"supported"\}\})'

    matches = list(re.finditer(pattern1, content))
    if len(matches) >= 2:
        # Two matches: first is chillingSlothFeat (skip), second is quietPenguin (patch)
        m = matches[1]
        replacement = m.group(1) + m.group(2) + m.group(3) + m.group(4)
        content = content[:m.start()] + replacement + content[m.end():]
        print(f"  [OK] quietPenguin ({matches[1].group(2).decode()}): patched (chillingSlothFeat {matches[0].group(2).decode()} skipped)")
    elif len(matches) == 1:
        # Only one match — assume it's quietPenguin, patch it
        m = matches[0]
        replacement = m.group(1) + m.group(2) + m.group(3) + m.group(4)
        content = content[:m.start()] + replacement + content[m.end():]
        print(f"  [OK] quietPenguin ({matches[0].group(2).decode()}): 1 match")
    else:
        print(f"  [FAIL] darwin-gated functions: 0 matches, expected at least 1")
        failed = True

    # Check results
    if failed:
        print("  [FAIL] Required patterns did not match")
        return False

    # Patch 2: Gate chillingSlothLocal on Linux
    # This function only gates Windows ARM64, but returns {status:"supported"} on Linux.
    # The web app uses chillingSlothLocal to show the Cowork tab. We need to return
    # "unavailable" on Linux since Cowork requires ClaudeVM.
    #
    # Original: function XXX(){return process.platform==="win32"&&process.arch==="arm64"?{status:"unsupported",...}:{status:"supported"}}
    # Changed:  function XXX(){if(process.platform==="linux")return{status:"unavailable"};return ...original...}
    pattern2_local = rb'(function \w+\(\)\{return )(process\.platform==="win32"&&process\.arch==="arm64"\?\{status:"unsupported",reason:"Local sessions are not supported on Windows ARM64"\}:\{status:"supported"\})'

    replacement2_local = rb'\1process.platform==="linux"?{status:"unavailable"}:\2'

    content, count2_local = re.subn(pattern2_local, replacement2_local, content)
    if count2_local >= 1:
        print(f"  [OK] chillingSlothLocal Linux gate: {count2_local} match(es)")
    else:
        print(f"  [WARN] chillingSlothLocal: 0 matches (pattern may have changed)")

    # Patch 3: Override features in mC() async merger
    # The mC() function merges Oh() with async overrides. Features wrapped by QL()
    # in Oh() are blocked in production. We append overrides after the last async
    # property so they take precedence over the ...Oh() spread.
    #
    # We override:
    # - quietPenguin/louderPenguin → "supported" (Code tab, bypasses QL gate)
    # NOTE: Cowork tab visibility is controlled server-side by the claude.ai web app,
    #   not by these desktop feature flags. Hiding it requires CSS injection
    #   (see fix_hide_cowork_tab.py).
    #
    # Before: desktopVoiceDictation:await XXX()})
    # After:  desktopVoiceDictation:await XXX(),quietPenguin:...,louderPenguin:...,chillingSloth*:...})
    pattern3 = rb'(desktopVoiceDictation:await \w+\(\))\}\)'
    replacement3 = rb'\1,quietPenguin:{status:"supported"},louderPenguin:{status:"supported"}})'

    content, count3 = re.subn(pattern3, replacement3, content)
    if count3 >= 1:
        print(f"  [OK] mC() feature merger: 2 Code features overridden ({count3} match)")
    else:
        print(f"  [FAIL] mC() feature merger: 0 matches, expected 1")
        failed = True

    # Check results
    if failed:
        print("  [FAIL] Required patterns did not match")
        return False

    # Patch 4: Change preferences defaults for Code features
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
        print("  [PASS] Code features enabled successfully (Cowork/chillingSlothFeat intentionally left gated)")
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
