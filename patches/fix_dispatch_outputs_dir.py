#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Fix "Show folder" opening empty outputs directory for dispatch sessions.

When a dispatch (Ditto) session spawns a child session to do work, the child
creates files in its own outputs directory:
  .../local_<child-uuid>/outputs/Son_Goku.pdf

But "Show folder" in the UI calls openOutputsDir with the dispatch parent's
session ID, which resolves to a different (empty) directory:
  .../agent/local_ditto_<conversation-id>/outputs/  (empty)

On macOS/Windows this doesn't happen because the VM filesystem is shared
across all sessions. On Linux with the native Go backend, each session has
its own directory.

Fix: When the requested outputs dir is empty, scan sibling session
directories (same account storage) for a child outputs dir that has files.
Open that directory instead.

Usage: python3 fix_dispatch_outputs_dir.py <path_to_index.js>
"""

import sys
import os
import re


EXPECTED_PATCHES = 1


def patch_outputs_dir(filepath):
    """Patch openOutputsDir to fall back to child session outputs."""

    print("=== Patch: fix_dispatch_outputs_dir ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, "rb") as f:
        content = f.read()

    original_content = content
    patches_applied = 0

    # ── Patch A: openOutputsDir child fallback ───────────────────────
    #
    # Upstream: opens the dispatch parent's outputs dir (often empty).
    # Patched: if empty, scan sibling session dirs for non-empty outputs.
    #
    # Directory structure:
    #   accountDir/agent/local_ditto_<id>/outputs/     ← dispatch parent (empty)
    #   accountDir/local_<child-uuid>/outputs/          ← child (has files)
    #
    # We go up from the outputs dir to the account dir and scan local_* dirs.
    #
    # Variable names change between versions (T→X, Ae→Be, e→t, etc.),
    # so we use [\w$]+ wildcards and capture groups.
    # For fs/path in the injected code, we use require() directly instead
    # of relying on minified module aliases.

    pattern_a = (
        rb"async openOutputsDir\(([\w$]+)\)\{"
        rb"const ([\w$]+)=([\w$]+)\.getOutputsDir\(\1\);"
        rb"([\w$]+)\.info\(`LocalAgentModeSessions\.openOutputsDir: sessionId=\$\{\1\}, outputsDir=\$\{\2\}`\);"
        rb"const ([\w$]+)=await ([\w$]+)\.shell\.openPath\(\2\);"
        rb"\5&&\4\.error\(`Failed to open outputs directory: \$\{\2\}, error: \$\{\5\}`\)\}"
    )

    def replacement_a(m):
        p = m.group(1).decode()  # param name (e.g. n)
        d = m.group(2).decode()  # outputs dir var (e.g. i)
        c = m.group(3).decode()  # class instance (e.g. e)
        L = m.group(4).decode()  # logger (e.g. T)
        s = m.group(5).decode()  # error var (e.g. s)
        E = m.group(6).decode()  # electron module (e.g. Ae)

        return (
            f"async openOutputsDir({p}){{"
            f"const {d}={c}.getOutputsDir({p});"
            f"{L}.info(`LocalAgentModeSessions.openOutputsDir: sessionId=${{{p}}}, outputsDir=${{{d}}}`);"
            f"let _td={d};"
            f"try{{"
            f'const _fs=require("fs"),_pa=require("path");'
            f'const _fl=_fs.readdirSync({d}).filter(f=>!f.startsWith("."));'
            f"if(_fl.length===0){{"
            f'{L}.info("[openOutputsDir] outputs empty, scanning child sessions...");'
            f'const _ad=_pa.dirname(_pa.dirname({d}.includes("/agent/")?_pa.dirname({d}):{d}));'
            f"try{{"
            f"const _en=_fs.readdirSync(_ad,{{withFileTypes:true}});"
            f"for(const _et of _en){{"
            f'if(!_et.isDirectory()||_et.name==="agent")continue;'
            f'const _co=_pa.join(_ad,_et.name,"outputs");'
            f"try{{"
            f'const _cf=_fs.readdirSync(_co).filter(f=>!f.startsWith("."));'
            f"if(_cf.length>0){{{L}.info(`[openOutputsDir] found files in child: ${{_co}}`);_td=_co;break}}"
            f"}}catch(_e){{}}"
            f"}}"
            f"}}catch(_e){{}}"
            f"}}"
            f"}}catch(_e){{}}"
            f"const {s}=await {E}.shell.openPath(_td);"
            f"{s}&&{L}.error(`Failed to open outputs directory: ${{_td}}, error: ${{{s}}}`)}}"
        ).encode()

    already_a = b"[openOutputsDir] outputs empty, scanning child sessions" in content
    if already_a:
        print("  [OK] A openOutputsDir: already patched (skipped)")
        patches_applied += 1
    else:
        content, count = re.subn(pattern_a, replacement_a, content)
        if count == 1:
            print("  [OK] A openOutputsDir: child session fallback added")
            patches_applied += 1
        else:
            print(f"  [FAIL] A openOutputsDir: expected 1 match, found {count}")

    if patches_applied < EXPECTED_PATCHES:
        print(f"  [FAIL] Only {patches_applied}/{EXPECTED_PATCHES} patches applied")
        return False

    if content != original_content:
        with open(filepath, "wb") as f:
            f.write(content)
        print("  [PASS] Dispatch outputs directory fallback added")
        return True
    else:
        print("  [OK] Already patched, no changes needed")
        return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_outputs_dir(sys.argv[1])
    sys.exit(0 if success else 1)
