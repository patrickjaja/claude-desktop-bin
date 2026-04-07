#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Prevent 'app.asar' from being used as workspace directory on Linux.

On first launch on Linux, the workspace trust dialog may show "app.asar"
as the workspace directory. This happens because the web app (claude.ai)
can resolve app.getAppPath() as the default workspace, which on Linux
points to the .asar file rather than a user directory.

This patch sanitizes workspace paths at the IPC bridge layer: any path
containing "app.asar" is redirected to os.homedir() on Linux. This
prevents both the confusing trust dialog and sessions starting in the
wrong directory.

Patched bridge functions:
  - checkTrust    — workspace trust check
  - saveTrust     — workspace trust save
  - start         — session start (cwd field)
  - startCodeSession (×2) — code session start (first arg = cwd)

Usage: python3 fix_asar_workspace_cwd.py <path_to_index.js>
"""

import sys
import os
import re


def patch_asar_workspace(filepath):
    """Redirect app.asar workspace paths to home directory on Linux."""

    print("=== Patch: fix_asar_workspace_cwd ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, "rb") as f:
        content = f.read()

    # ── Idempotency check ────────────────────────────────────────────
    if b"__cdb_sanitizeCwd" in content:
        print("  [SKIP] Already patched (__cdb_sanitizeCwd found)")
        return True

    original_content = content
    patches_applied = 0

    # ── 1. Inject helper function ────────────────────────────────────
    #
    # On Linux, if a workspace path contains "app.asar", redirect to
    # the user's home directory. This is safe because Claude should
    # never use app.asar as a working directory.
    #
    # Inject at file scope (after initial "use strict";) so it's
    # accessible everywhere.

    SANITIZE_FN = b'var __cdb_sanitizeCwd=function(p){if(process.platform==="linux"&&typeof p==="string"&&/app\\.asar/.test(p)){return require("os").homedir()}return p};'

    # Inject at the very beginning of the file, after "use strict";
    use_strict = b'"use strict";'
    idx = content.find(use_strict)
    if idx >= 0:
        inject_point = idx + len(use_strict)
        content = content[:inject_point] + SANITIZE_FN + content[inject_point:]
        print("  [OK] Injected __cdb_sanitizeCwd helper (after 'use strict')")
    else:
        # Fallback: inject at very start
        content = SANITIZE_FN + content
        print("  [OK] Injected __cdb_sanitizeCwd helper (at file start)")

    # ── 2. Patch checkTrust bridge ───────────────────────────────────
    #
    # Before: checkTrust(a){return X.info(`...`),e.checkWorkspaceTrust(a)}
    # After:  checkTrust(a){a=__cdb_sanitizeCwd(a);return X.info(`...`),e.checkWorkspaceTrust(a)}

    pat_ct = rb"(checkTrust\()([\w$]+)(\)\{)(return [\w$]+\.info\()"

    def repl_ct(m):
        arg = m.group(2)
        return m.group(1) + arg + m.group(3) + arg + b"=__cdb_sanitizeCwd(" + arg + b");" + m.group(4)

    content, count = re.subn(pat_ct, repl_ct, content, count=1)
    if count > 0:
        patches_applied += count
        print(f"  [OK] checkTrust bridge: {count} match(es)")
    else:
        print("  [WARN] checkTrust bridge: 0 matches")

    # ── 3. Patch saveTrust bridge ────────────────────────────────────
    #
    # Before: async saveTrust(a){X.info(`...`),await e.saveWorkspaceTrust(a)}
    # After:  async saveTrust(a){a=__cdb_sanitizeCwd(a);X.info(`...`),...}

    pat_st = rb"(async saveTrust\()([\w$]+)(\)\{)([\w$]+\.info\()"

    def repl_st(m):
        arg = m.group(2)
        return m.group(1) + arg + m.group(3) + arg + b"=__cdb_sanitizeCwd(" + arg + b");" + m.group(4)

    content, count = re.subn(pat_st, repl_st, content, count=1)
    if count > 0:
        patches_applied += count
        print(f"  [OK] saveTrust bridge: {count} match(es)")
    else:
        print("  [WARN] saveTrust bridge: 0 matches")

    # ── 4. Patch start bridge ────────────────────────────────────────
    #
    # Before: async start(a){return X.info("LocalSessions.start:"),...
    # After:  async start(a){a.cwd=__cdb_sanitizeCwd(a.cwd);return ...

    pat_start = (
        rb"(async start\()([\w$]+)"
        rb'(\)\{)(return [\w$]+\.info\("LocalSessions\.start:"\))'
    )

    def repl_start(m):
        arg = m.group(2)
        return m.group(1) + arg + m.group(3) + arg + b".cwd=__cdb_sanitizeCwd(" + arg + b".cwd);" + m.group(4)

    content, count = re.subn(pat_start, repl_start, content, count=1)
    if count > 0:
        patches_applied += count
        print(f"  [OK] start bridge: {count} match(es)")
    else:
        print("  [WARN] start bridge: 0 matches")

    # ── 5. Patch startCodeSession bridges ────────────────────────────
    #
    # Two handlers: local CCD and dispatch/cowork. Both take cwd as
    # first argument.
    #
    # Pattern: startCodeSession:X?async(De,ze,Ze,Ye)=>{...
    # After:   startCodeSession:X?async(De,ze,Ze,Ye)=>{De=__cdb_sanitizeCwd(De);...

    pat_scs = (
        rb"(startCodeSession:[\w$]+\?async\()([\w$]+)"
        rb"(,[\w$]+,[\w$]+,[\w$]+\)=>\{)"
    )

    def repl_scs(m):
        arg = m.group(2)
        return m.group(1) + arg + m.group(3) + arg + b"=__cdb_sanitizeCwd(" + arg + b");"

    content, count = re.subn(pat_scs, repl_scs, content)
    if count > 0:
        patches_applied += count
        print(f"  [OK] startCodeSession bridges: {count} match(es)")
    else:
        print("  [WARN] startCodeSession bridges: 0 matches")

    # Also patch the dispatch startCodeSession (different signature)
    # Pattern: startCodeSession:async(V,q,j,W)=>{
    pat_scs2 = (
        rb"(startCodeSession:async\()([\w$]+)"
        rb"(,[\w$]+,[\w$]+,[\w$]+\)=>\{)"
    )

    def repl_scs2(m):
        arg = m.group(2)
        return m.group(1) + arg + m.group(3) + arg + b"=__cdb_sanitizeCwd(" + arg + b");"

    content, count = re.subn(pat_scs2, repl_scs2, content)
    if count > 0:
        patches_applied += count
        print(f"  [OK] dispatch startCodeSession: {count} match(es)")
    else:
        print("  [WARN] dispatch startCodeSession: 0 matches")

    # ── Write back ───────────────────────────────────────────────────
    EXPECTED_PATCHES = 5
    if patches_applied < EXPECTED_PATCHES:
        print(f"  [FAIL] Only {patches_applied}/{EXPECTED_PATCHES} patches applied — check [WARN]/[FAIL] messages above")
        return False

    if content == original_content:
        print(f"  [OK] All {patches_applied} patches already applied (no changes needed)")
        return True

    with open(filepath, "wb") as f:
        f.write(content)
    print(f"  [PASS] {patches_applied} patches applied")
    return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_asar_workspace(sys.argv[1])
    sys.exit(0 if success else 1)
