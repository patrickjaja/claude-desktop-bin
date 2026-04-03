#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Prevent app.asar from being treated as a folder drop on Linux.

When Claude Desktop is re-launched (e.g. by an OAuth callback or
claude:// URL handler), the second instance sends its argv to the
running first instance via Electron's second-instance event. The
argv contains "app.asar" as the first argument. The first instance's
argument parser calls fs.statSync(path).isDirectory() on each arg —
and because Electron's ASAR-aware fs layer treats .asar files as
directories, app.asar passes the directory check and gets dispatched
as a "folder drop" to the Cowork tab.

This triggers the "Allow Claude to change files in 'app.asar'?"
permission dialog, confusing users on first launch.

Fix: patch the isDirectory helper (t$e) to reject paths containing
"app.asar" on Linux before the statSync call.

See: https://github.com/patrickjaja/claude-desktop-bin/issues/24

Usage: python3 fix_asar_folder_drop.py <path_to_index.js>
"""

import sys
import os
import re


def patch_asar_folder_drop(filepath):
    """Filter app.asar paths from the folder-drop directory check."""

    print("=== Patch: fix_asar_folder_drop ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, "rb") as f:
        content = f.read()

    # ── Idempotency check ────────────────────────────────────────────
    if b"__cdb_isAsarPath" in content:
        print("  [SKIP] Already patched (__cdb_isAsarPath found)")
        return True

    original_content = content

    # ── Patch the isDirectory helper ─────────────────────────────────
    #
    # Before:
    #   function t$e(t){try{return et.statSync(t).isDirectory()}catch{return!1}}
    #
    # After:
    #   function t$e(t){try{return!__cdb_isAsarPath(t)&&et.statSync(t).isDirectory()}catch{return!1}}
    #
    # The variable names (t$e, et) change between versions, so we use
    # flexible patterns.

    pat = (
        rb"(function \w+\$?\w*\(\w+\)\{try\{return )"
        rb"(\w+\.statSync\(\w+\)\.isDirectory\(\))"
        rb"(\}catch\{return!1\}\})"
        rb"(function \w+\(\w+,\w+,\w+\)\{)"
    )

    def repl(m):
        # Inject a guard: if path contains "app.asar", return false
        # Extract the argument name from the function signature
        func_head = m.group(1)
        # Find the argument name (single char between parens)
        arg_match = re.search(rb"\((\w+)\)", func_head)
        if not arg_match:
            return m.group(0)  # safety: don't patch if we can't find arg
        arg = arg_match.group(1)
        return func_head + b"!__cdb_isAsarPath(" + arg + b")&&" + m.group(2) + m.group(3) + m.group(4)

    content, count = re.subn(pat, repl, content, count=1)

    if count == 0:
        print("  [WARN] isDirectory helper pattern: 0 matches")
        # Fallback: try without the trailing function context
        pat2 = (
            rb"(function \w+\$?\w*\(\w+\)\{try\{return )"
            rb"(\w+\.statSync\(\w+\)\.isDirectory\(\))"
            rb"(\}catch\{return!1\}\})"
        )

        def repl2(m):
            func_head = m.group(1)
            arg_match = re.search(rb"\((\w+)\)", func_head)
            if not arg_match:
                return m.group(0)
            arg = arg_match.group(1)
            return func_head + b"!__cdb_isAsarPath(" + arg + b")&&" + m.group(2) + m.group(3)

        content, count = re.subn(pat2, repl2, content, count=1)
        if count > 0:
            print(f"  [OK] isDirectory helper (fallback pattern): {count} match(es)")
        else:
            print("  [FAIL] isDirectory helper: no pattern matched")
            return False
    else:
        print(f"  [OK] isDirectory helper: {count} match(es)")

    # ── Inject the helper function ───────────────────────────────────
    #
    # Simple check: on Linux, reject any path containing "app.asar".
    # Placed right before the patched function for locality.

    HELPER = b'var __cdb_isAsarPath=function(p){return process.platform==="linux"&&typeof p==="string"&&/app\\.asar/.test(p)};'

    # Inject after "use strict"; (same strategy as fix_asar_workspace_cwd.py)
    use_strict = b'"use strict";'
    idx = content.find(use_strict)
    if idx >= 0:
        inject_point = idx + len(use_strict)
        content = content[:inject_point] + HELPER + content[inject_point:]
        print("  [OK] Injected __cdb_isAsarPath helper")
    else:
        content = HELPER + content
        print("  [OK] Injected __cdb_isAsarPath helper (at file start)")

    # ── Write back ───────────────────────────────────────────────────
    if content != original_content:
        with open(filepath, "wb") as f:
            f.write(content)
        print("  [PASS] Patch applied")
        return True
    else:
        print("  [WARN] No changes made")
        return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_asar_folder_drop(sys.argv[1])
    sys.exit(0 if success else 1)
