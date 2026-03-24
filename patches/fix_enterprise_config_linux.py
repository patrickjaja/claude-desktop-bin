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

    print(f"=== Patch: fix_enterprise_config_linux ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, 'rb') as f:
        content = f.read()

    # Idempotency check: skip if already patched
    if b'/etc/claude-desktop/enterprise.json' in content:
        print("  [OK] Already patched (enterprise.json path found)")
        print("  [PASS] No changes needed")
        return True

    # Pattern: the default case in the platform switch inside the enterprise
    # config loader function (af/similar).
    #
    # Original:
    #   case"win32":VAR=FUNC();break;default:VAR={};break
    #
    # Patched:
    #   case"win32":VAR=FUNC();break;default:VAR=function(){try{return JSON.parse(
    #     require("fs").readFileSync("/etc/claude-desktop/enterprise.json","utf8")
    #   )}catch(e){return{}}}();break
    #
    # The self-invoking function reads and parses the JSON file. If the file
    # doesn't exist or contains invalid JSON, catch returns {} (same as before).
    #
    # Variable names are minified and change between versions — use \w+.
    pattern = rb'(case"win32":(\w+)=\w+\(\);break;default:)\2(=\{\};break)'

    def replacement(m):
        prefix = m.group(1)       # case"win32":Tb=ztr();break;default:
        cache_var = m.group(2)    # Tb
        linux_reader = (
            b'=function(){try{return JSON.parse('
            b'require("fs").readFileSync("/etc/claude-desktop/enterprise.json","utf8")'
            b')}catch(e){return{}}}();break'
        )
        return prefix + cache_var + linux_reader

    content, count = re.subn(pattern, replacement, content)
    if count >= 1:
        print(f"  [OK] Enterprise config Linux reader: {count} match(es)")
    else:
        print(f"  [FAIL] Enterprise config default case: 0 matches")
        return False

    # Write back
    with open(filepath, 'wb') as f:
        f.write(content)
    print("  [PASS] Enterprise config Linux support added")
    return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_enterprise_config_linux(sys.argv[1])
    sys.exit(0 if success else 1)
