#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Force CCD mode for marketplace operations on Linux.

The CCD/Cowork gate function determines whether plugin operations use
host-local CCD paths or account-scoped Cowork paths. On Linux there's
no VM, so all operations should use the CCD (host-local) path.

This patch makes the gate function return true on Linux by prepending
a process.platform check, so all plugin operations (getPlugins,
uploadPlugin, deletePlugin, setPluginEnabled) use host-local paths.

Original:  function vu(t){return(t==null?void 0:t.mode)==="ccd"}
Patched:   function vu(t){return process.platform==="linux"||(t==null?void 0:t.mode)==="ccd"}

Note: Function name changes between versions (Hb, Gw, vu, etc.).

Usage: python3 fix_marketplace_linux.py <path_to_index.js>
"""

import sys
import os
import re


def patch_marketplace_linux(filepath):
    """Force CCD mode for marketplace operations on Linux."""

    print("=== Patch: fix_marketplace_linux ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, "rb") as f:
        content = f.read()

    original_content = content

    # Idempotency check: the patched version has the platform check before the mode check
    idempotency_pattern = rb'function [\w$]+\([\w$]+\)\{return process\.platform==="linux"\|\|'
    if re.search(idempotency_pattern, content):
        print("  [OK] Already patched (Linux platform check found in CCD gate)")
        print("  [PASS] No changes needed")
        return True

    # CCD/Cowork gate — force CCD mode on Linux
    #
    # The gate function is called throughout the plugin system.
    # When it returns true, operations use host-local CCD paths.
    # When false, they use account-scoped Cowork paths.
    # On Linux there's no VM, so all operations should use the CCD path.
    #
    # Original: function $S(t){return(t==null?void 0:t.mode)==="ccd"}
    # Patched:  function $S(t){return process.platform==="linux"||(t==null?void 0:t.mode)==="ccd"}
    #
    # Function name may contain $ (valid JS identifier), so use [\w$]+.
    pattern = rb'function ([\w$]+)\(([\w$]+)\)\{return\((\2)==null\?void 0:\3\.mode\)==="ccd"\}'

    def replacement(m):
        fn_name = m.group(1)
        param = m.group(2)
        return b"function " + fn_name + b"(" + param + b'){return process.platform==="linux"||(' + param + b"==null?void 0:" + param + b'.mode)==="ccd"}'

    content, count = re.subn(pattern, replacement, content)
    if count >= 1:
        print(f"  [OK] CCD/Cowork gate: force CCD mode on Linux ({count} match)")
    else:
        print("  [FAIL] CCD/Cowork gate: 0 matches")
        return False

    if content == original_content:
        print("  [WARN] No changes made (pattern may have already been applied)")
        return True

    # Write back
    with open(filepath, "wb") as f:
        f.write(content)
    print("  [PASS] Marketplace Linux patch applied")
    return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_marketplace_linux(sys.argv[1])
    sys.exit(0 if success else 1)
