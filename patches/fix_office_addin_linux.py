#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Enable Office Addin (louderPenguin) feature on Linux.

The Office Addin integration lets Claude connect to Microsoft Office documents
(Word, Excel, PowerPoint) for context-aware assistance. It is gated behind
the "louderPenguinEnabled" feature flag AND a platform check that only allows
macOS (process.platform==="darwin") and Windows (process.platform==="win32").

The platform check uses two minified boolean variables (e.g. `ui` and `as`)
that evaluate to `process.platform==="darwin"` and `process.platform==="win32"`
respectively. These variable names change between upstream releases.

Three-part patch (A-C):

A. MCP server isEnabled gate.
   The Office Addin MCP server's isEnabled callback checks:
     (Qn("4116586025")||!1||!1)&&(VAR||VAR)&&En("louderPenguinEnabled")
   We add ||process.platform==="linux" inside the platform check parens.

B. Init block gate.
   The Office Addin initialization block is guarded by:
     (VAR||VAR)&&En("louderPenguinEnabled")&&(VW(...))
   We add ||process.platform==="linux" inside the platform check parens.

C. Connected file detection gate.
   When focusing a file from an Office app, the code checks:
     (VAR||VAR)&&await CZr(e.app,e.document)
   We add ||process.platform==="linux" inside the platform check parens.

Usage: python3 fix_office_addin_linux.py <path_to_index.js>
"""

import sys
import os
import re


def patch_office_addin_linux(filepath):
    """Enable Office Addin feature on Linux."""

    print(f"=== Patch: fix_office_addin_linux ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content
    patches_applied = 0

    # ── Patch A: MCP server isEnabled gate ────────────────────────────────
    #
    # Original:
    #   isEnabled:()=>(Qn("4116586025")||!1||!1)&&(ui||as)&&En("louderPenguinEnabled")
    #
    # The (VAR||VAR) is the platform check (darwin || win32). We add Linux.
    #
    # Pattern anchors on `&&(` before and `)&&En("louderPenguinEnabled")` after.
    # Uses \w+ for all minified variable names.

    pattern_a = rb'(&&\()(\w+\|\|\w+)(\)&&\w+\("louderPenguinEnabled"\))'
    already_a = rb'&&\(\w+\|\|\w+\|\|process\.platform==="linux"\)&&\w+\("louderPenguinEnabled"\)'

    if re.search(already_a, content):
        print(f"  [OK] MCP server isEnabled: already patched (skipped)")
        patches_applied += 1
    else:
        def replacement_a(m):
            return m.group(1) + m.group(2) + b'||process.platform==="linux"' + m.group(3)

        content, count_a = re.subn(pattern_a, replacement_a, content)
        if count_a >= 1:
            print(f"  [OK] MCP server isEnabled: added Linux ({count_a} match)")
            patches_applied += 1
        else:
            print(f"  [FAIL] MCP server isEnabled: pattern not found")

    # ── Patch B: Init block gate ──────────────────────────────────────────
    #
    # Original:
    #   });(ui||as)&&En("louderPenguinEnabled")&&(VW(k7t,l8n,()=>EZ),...)
    #
    # This is the top-level init statement that registers the Office Addin
    # IPC handlers and starts the connection flow. The (VAR||VAR) is at the
    # start of the statement, preceded by `});`.
    #
    # Pattern anchors on `});(` before and `)&&En("louderPenguinEnabled")&&(` after.

    pattern_b = rb'(\}\);\()(\w+\|\|\w+)(\)&&\w+\("louderPenguinEnabled"\)&&\()'
    already_b = rb'\}\);\(\w+\|\|\w+\|\|process\.platform==="linux"\)&&\w+\("louderPenguinEnabled"\)&&\('

    if re.search(already_b, content):
        print(f"  [OK] Init block: already patched (skipped)")
        patches_applied += 1
    else:
        def replacement_b(m):
            return m.group(1) + m.group(2) + b'||process.platform==="linux"' + m.group(3)

        content, count_b = re.subn(pattern_b, replacement_b, content)
        if count_b >= 1:
            print(f"  [OK] Init block: added Linux ({count_b} match)")
            patches_applied += 1
        else:
            print(f"  [FAIL] Init block: pattern not found")

    # ── Patch C: Connected file detection gate ────────────────────────────
    #
    # Original:
    #   if((ui||as)&&await CZr(e.app,e.document)){...}
    #
    # CZr() (name varies) detects connected Office files. The platform check
    # prevents it from running on Linux. We add Linux to the gate.
    #
    # Pattern anchors on `(` before and `)&&await VAR(VAR.app,VAR.document)` after.

    pattern_c = rb'(\()(\w+\|\|\w+)(\)&&await \w+\(\w+\.app,\w+\.document\))'
    already_c = rb'\(\w+\|\|\w+\|\|process\.platform==="linux"\)&&await \w+\(\w+\.app,\w+\.document\)'

    if re.search(already_c, content):
        print(f"  [OK] Connected file detection: already patched (skipped)")
        patches_applied += 1
    else:
        def replacement_c(m):
            return m.group(1) + m.group(2) + b'||process.platform==="linux"' + m.group(3)

        content, count_c = re.subn(pattern_c, replacement_c, content)
        if count_c >= 1:
            print(f"  [OK] Connected file detection: added Linux ({count_c} match)")
            patches_applied += 1
        else:
            print(f"  [FAIL] Connected file detection: pattern not found")

    # ── Results ───────────────────────────────────────────────────────────

    if patches_applied == 0:
        print("  [FAIL] No patches could be applied")
        return False

    if content == original_content:
        print("  [WARN] No changes made (patterns may have already been applied)")
        return True

    # Verify patches didn't introduce a brace imbalance
    original_delta = original_content.count(b'{') - original_content.count(b'}')
    patched_delta = content.count(b'{') - content.count(b'}')
    if original_delta != patched_delta:
        diff = patched_delta - original_delta
        print(f"  [FAIL] Patch introduced brace imbalance: {diff:+d} unmatched braces")
        return False

    # Write back
    with open(filepath, 'wb') as f:
        f.write(content)
    print(f"  [PASS] {patches_applied} patches applied")
    return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_office_addin_linux(sys.argv[1])
    sys.exit(0 if success else 1)
