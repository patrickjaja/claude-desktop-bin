#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Force host CLI runner for marketplace operations on Linux.

Marketplace operations (browse plugins, add marketplace, search plugins) are
routed through either the host runner (gz) or the Cowork VM runner (mz).
On the Cowork tab, the VM runner is selected, which shells out through the
daemon — this fails on Linux with MARKETPLACE_ERROR:UNKNOWN because the
daemon doesn't handle marketplace commands.

Since marketplace management is a host filesystem operation (it runs
`claude plugin marketplace list --json` etc.), we force the host runner
on Linux regardless of session type.

Three-part patch:
A. IPC bridge runner selector — `const e=r=><gate>(r)?<host>:<vm>`
   Add process.platform==="linux" to always pick the host runner on Linux.
B. search_plugins tool handler — `r.sessionType==="ccd"?<host>:<vm>`
   Same logic: force host runner on Linux.
C. CCD/Cowork gate function — `function <gate>(t){return(t==null?void 0:t.mode)==="ccd"}`
   Force true on Linux so all plugin operations (getPlugins, uploadPlugin,
   deletePlugin, setPluginEnabled) use host-local CCD paths instead of
   account-scoped Cowork paths. On Linux there's no VM, so the CCD path
   is always correct.
   Note: Function name changes between versions (Hb, Gw, etc.).

Usage: python3 fix_marketplace_linux.py <path_to_index.js>
"""

import sys
import os
import re


def patch_marketplace_linux(filepath):
    """Force host CLI runner for marketplace operations on Linux."""

    print(f"=== Patch: fix_marketplace_linux ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content
    patches_applied = 0

    # Patch A: oAt() IPC bridge runner selector
    #
    # Original: const e=r=>Hb(r)?gz:mz
    # Patched:  const e=r=>process.platform==="linux"||Hb(r)?gz:mz
    #
    # On Linux, the || short-circuits to true → always selects gz (host runner).
    # On other platforms, falls through to Hb(r) which checks CCD mode.
    #
    # Capture groups:
    #   1 = "const " + variable name + "="
    #   2 = parameter name (used in Hb() call)
    #   3 = host runner variable (gz)
    #   4 = VM runner variable (mz)
    pattern_a = rb'(const \w+=)(\w+)(=>(\w+)\(\2\)\?)(\w+):(\w+)'

    def replacement_a(m):
        gate_fn = m.group(4)  # The gate function name (Hb, Gw, etc.)
        return (m.group(1) + m.group(2) +
                b'=>process.platform==="linux"||' + gate_fn + b'(' + m.group(2) + b')?' +
                m.group(5) + b':' + m.group(6))

    content, count_a = re.subn(pattern_a, replacement_a, content)
    if count_a >= 1:
        print(f"  [OK] oAt() runner selector: force host runner on Linux ({count_a} match)")
        patches_applied += 1
    else:
        print(f"  [FAIL] oAt() runner selector: 0 matches")

    # Patch B: search_plugins tool handler
    #
    # Original: r.sessionType==="ccd"?gz:mz
    # Patched:  (process.platform==="linux"||r.sessionType==="ccd")?gz:mz
    #
    # Same logic as Patch A but in the search_plugins handler.
    #
    # Capture groups:
    #   1 = session variable (r)
    #   2 = host runner variable (gz)
    #   3 = VM runner variable (mz)
    pattern_b = rb'(\w+)(\.sessionType==="ccd"\?)(\w+):(\w+)'

    def replacement_b(m):
        return (b'(process.platform==="linux"||' + m.group(1) +
                b'.sessionType==="ccd")?' +
                m.group(3) + b':' + m.group(4))

    content, count_b = re.subn(pattern_b, replacement_b, content)
    if count_b >= 1:
        print(f"  [OK] search_plugins handler: force host runner on Linux ({count_b} match)")
        patches_applied += 1
    else:
        print(f"  [FAIL] search_plugins handler: 0 matches")

    # Patch C: Hb() — force CCD mode on Linux
    #
    # Hb() is the CCD/Cowork gate called throughout the plugin system.
    # When Hb() returns true, operations use host-local CCD paths (bq(), gz, oyt()).
    # When false, they use account-scoped Cowork paths (XA(), mz).
    # On Linux there's no VM, so all operations should use the CCD path.
    #
    # Original: function Hb(t){return(t==null?void 0:t.mode)==="ccd"}
    # Patched:  function Hb(t){return process.platform==="linux"||(t==null?void 0:t.mode)==="ccd"}
    #
    # This fixes 5 call sites at once: oAt() runner selector, getPlugins,
    # uploadPlugin, deletePlugin, and setPluginEnabled.
    #
    # Capture groups:
    #   1 = parameter name (e.g. "t")
    pattern_c = rb'function (\w+)\((\w+)\)\{return\((\2)==null\?void 0:\3\.mode\)==="ccd"\}'

    def replacement_c(m):
        fn_name = m.group(1)
        param = m.group(2)
        return (b'function ' + fn_name + b'(' + param + b'){return process.platform==="linux"||(' +
                param + b'==null?void 0:' + param + b'.mode)==="ccd"}')

    content, count_c = re.subn(pattern_c, replacement_c, content)
    if count_c >= 1:
        print(f"  [OK] Hb() CCD/Cowork gate: force CCD mode on Linux ({count_c} match)")
        patches_applied += 1
    else:
        print(f"  [FAIL] Hb() CCD/Cowork gate: 0 matches")

    # Check results
    if patches_applied == 0:
        print("  [FAIL] No patches could be applied")
        return False

    if content == original_content:
        print("  [WARN] No changes made (patterns may have already been applied)")
        return True

    # Write back
    with open(filepath, 'wb') as f:
        f.write(content)
    print(f"  [PASS] {patches_applied} patches applied")
    return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_marketplace_linux(sys.argv[1])
    sys.exit(0 if success else 1)
