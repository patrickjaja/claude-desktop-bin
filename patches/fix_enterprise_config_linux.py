#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Enable enterprise config on Linux.

The enterprise config function af() reads managed configuration:
- macOS: reads from CFPreferences (MDM profiles)
- Windows: reads from Windows Registry (Group Policy)
- Linux: returns {} (no enterprise config support)

This patch adds Linux support by reading from a JSON file at
/etc/claude-desktop/enterprise.json. If the file doesn't exist
or is invalid, falls back to {} (preserving current behavior).

Supported config keys (v1.1.8359):
  isDesktopExtensionEnabled, isDesktopExtensionDirectoryEnabled,
  isDesktopExtensionSignatureRequired, isLocalDevMcpEnabled,
  isClaudeCodeForDesktopEnabled, secureVmFeaturesEnabled,
  disableAutoUpdates, autoUpdaterEnforcementHours, customDeploymentUrl,
  isDxtEnabled, isDxtDirectoryEnabled, isDxtSignatureRequired,
  custom3pProvider, custom3pBaseUrl, custom3pApiKey,
  custom3pGcpProjectId, custom3pGcpRegion, custom3pGcpCredentialsFile,
  custom3pAwsRegion, custom3pAwsBearerToken, custom3pOrganizationKey,
  custom3pModels, custom3pEgressRules

Usage: python3 fix_enterprise_config_linux.py <path_to_index.js>
"""

import sys
import os
import re


def patch_enterprise_config_linux(filepath):
    """Add Linux enterprise config support via /etc/claude-desktop/enterprise.json."""

    print("=== Patch: fix_enterprise_config_linux ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, "rb") as f:
        content = f.read()

    # Idempotency check: skip if already patched
    if b"/etc/claude-desktop/enterprise.json" in content:
        print("  [OK] Already patched (enterprise.json path found)")
        print("  [PASS] No changes needed")
        return True

    # Pattern: the ternary chain in enterprise config loader functions.
    #
    # Original (v1.2278.0+):
    #   process.platform==="darwin"?FUNC_D():process.platform==="win32"?FUNC_W():{}
    #
    # Patched — add Linux branch before the fallback {}:
    #   process.platform==="darwin"?FUNC_D():process.platform==="win32"?FUNC_W():
    #     process.platform==="linux"?(()=>{try{return JSON.parse(
    #       require("fs").readFileSync("/etc/claude-desktop/enterprise.json","utf8")
    #     )}catch(e){return{}}})():{}
    #
    # This appears in two functions (gUt/r8r or similar). Replace all occurrences.
    pattern = rb'process\.platform==="darwin"\?([\w$]+)\(\):process\.platform==="win32"\?([\w$]+)\(\):\{\}'

    linux_reader = b'process.platform==="linux"?(()=>{try{return JSON.parse(require("fs").readFileSync("/etc/claude-desktop/enterprise.json","utf8"))}catch(e){return{}}})():{}'

    def replacement(m):
        darwin_fn = m.group(1)
        win32_fn = m.group(2)
        return b'process.platform==="darwin"?' + darwin_fn + b'():process.platform==="win32"?' + win32_fn + b"():" + linux_reader

    content, count = re.subn(pattern, replacement, content)
    if count >= 1:
        print(f"  [OK] Enterprise config Linux reader: {count} match(es)")
    else:
        print("  [FAIL] Enterprise config default case: 0 matches")
        return False

    # Write back
    with open(filepath, "wb") as f:
        f.write(content)
    print("  [PASS] Enterprise config Linux support added")

    # Also patch index.pre.js if it exists (early bootstrap enterprise config)
    pre_js = os.path.join(os.path.dirname(filepath), "index.pre.js")
    if os.path.exists(pre_js):
        with open(pre_js, "rb") as f:
            pre_content = f.read()
        if b"/etc/claude-desktop/enterprise.json" in pre_content:
            print("  [OK] index.pre.js: already patched")
        else:
            pre_content, pre_count = re.subn(pattern, replacement, pre_content)
            if pre_count >= 1:
                with open(pre_js, "wb") as f:
                    f.write(pre_content)
                print(f"  [OK] index.pre.js: enterprise config patched ({pre_count} match)")
            else:
                print("  [INFO] index.pre.js: no matching pattern (optional)")

    return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_enterprise_config_linux(sys.argv[1])
    sys.exit(0 if success else 1)
