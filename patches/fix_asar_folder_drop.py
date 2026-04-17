#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Prevent app.asar from being dispatched to Cowork on Linux.

When Claude Desktop is re-launched (e.g. by an OAuth callback,
claude:// URL handler, or clicking the launcher while running), the
second instance sends its argv to the running first instance via
Electron's second-instance event. The argv contains the app.asar path.

On Linux, Electron's ASAR-aware filesystem makes .asar files appear as
valid paths via existsSync()/statSync(), so app.asar from process.argv
passes through the existing filters and gets dispatched as a dropped
file on every launch.

The existing __cdb_isAsarPath / __cdb_sanitizeCwd patches catch the CWD
and isDirectory (folder detection) cases, but don't cover the file-drop
path through noe().

Fix (two layers):
1. Filter .asar paths at the top of noe() — this is the single
   convergence point for ALL file-drop code paths (second-instance,
   startup argv, open-file events), so one guard catches everything.
2. Guard the second-instance argv parser (KXn) to skip app.asar early,
   preventing unnecessary processing.

Credit: @dvolonnino for identifying the noe() convergence point.
See: https://github.com/patrickjaja/claude-desktop-bin/issues/24

Usage: python3 fix_asar_folder_drop.py <path_to_index.js>
"""

import sys
import os
import re

# Expected sub-patches:
#   A. noe() file-drop convergence filter (.asar)
#   B. Second-instance argv parser (KXn) .asar guard
EXPECTED_PATCHES = 2


def patch_asar_folder_drop(filepath):
    """Filter app.asar paths from file-drop dispatch."""

    print("=== Patch: fix_asar_folder_drop ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, "rb") as f:
        content = f.read()

    patches_applied = 0

    # ── Idempotency check ────────────────────────────────────────────
    # Check for the noe() .asar filter (primary fix)
    if re.search(rb"function [\w$]+\([\w$]+\)\{[\w$]+=[\w$]+\.filter\([\w$]+=>!/\\\.asar/", content):
        print("  [SKIP] Already patched (.asar filter found)")
        return True

    original_content = content

    # ── 1. Patch file-drop convergence point ─────────────────────────
    #
    # All file-drop code paths (second-instance argv, startup argv,
    # open-file events) converge through a single function (noe/Coe/etc,
    # name changes each release). Filter .asar paths here so nothing
    # slips through.
    #
    # Before:
    #   function Coe(t){if(R.info(`Handling file drop: ${t.join(", ")}`),...
    #
    # After:
    #   function Coe(t){t=t.filter(f=>!/\.asar/.test(f));if(!t.length)return;if(R.info(`Handling file drop: ${t.join(", ")}`),...

    pat_noe = (
        rb"(function [\w$]+\()([\w$]+)(\)\{)"
        rb"(if\([\w$]+\.info\(`Handling file drop:)"
    )

    def repl_noe(m):
        arg = m.group(2)
        return m.group(1) + arg + m.group(3) + arg + rb"=" + arg + rb".filter(f=>!/\.asar/.test(f));if(!" + arg + rb".length)return;" + m.group(4)

    content, count = re.subn(pat_noe, repl_noe, content, count=1)

    if count > 0:
        print(f"  [OK] noe() file-drop filter: {count} match(es)")
        patches_applied += 1
    else:
        print("  [FAIL] noe() pattern: 0 matches")
        return False

    # ── 2. Guard second-instance argv parser (defense-in-depth) ──────
    #
    # The KXn function (second-instance argv parser) iterates
    # argv.slice(1) and dispatches paths. Unlike the first-instance
    # startup code (VXn) which filters via `path.resolve(s) !== appPath`,
    # KXn has no such filter.
    #
    # Before:
    #   for(const n of t.slice(1))if(!GXn(n)){...
    #
    # After:
    #   for(const n of t.slice(1))if(!/\.asar/.test(n)&&!GXn(n)){...

    pat_argv = (
        rb"(for\(const )([\w$]+)( of [\w$]+\.slice\(1\)\))"
        rb"(if\()(![\w$]+\(\2\))"
    )

    def repl_argv(m):
        var = m.group(2)
        return m.group(1) + var + m.group(3) + m.group(4) + rb"!/\.asar/.test(" + var + rb")&&" + m.group(5)

    content, count = re.subn(pat_argv, repl_argv, content, count=1)

    if count > 0:
        print(f"  [OK] Second-instance argv parser (KXn): {count} match(es)")
        patches_applied += 1
    else:
        print("  [FAIL] Second-instance argv parser: 0 matches")

    # ── Enforce strictness ───────────────────────────────────────────
    if patches_applied < EXPECTED_PATCHES:
        print(f"  [FAIL] Only {patches_applied}/{EXPECTED_PATCHES} patches applied")
        return False

    # ── Write back ───────────────────────────────────────────────────
    if content != original_content:
        with open(filepath, "wb") as f:
            f.write(content)
        print(f"  [PASS] Patch applied ({patches_applied}/{EXPECTED_PATCHES} patches applied)")
        return True
    else:
        print(f"  [FAIL] No changes made ({patches_applied}/{EXPECTED_PATCHES} patches applied)")
        return False


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_asar_folder_drop(sys.argv[1])
    sys.exit(0 if success else 1)
