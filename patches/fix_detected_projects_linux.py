#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Enable Detected Projects (Recent Projects) on Linux.

The upstream code gates the entire project-detection pipeline behind a
`process.platform !== "darwin"` check, so Linux always gets an empty list.
The detection itself is platform-neutral (SQLite queries + directory scans)
— only the *paths* to IDE state databases differ between macOS and Linux.

This patch makes three changes:

1.  Platform guard — adds `&& process.platform !== "linux"` so the
    early-return in the detection entry-point no longer fires on Linux.

2.  VSCode / Cursor DB path — wraps the macOS-only
        ~/Library/Application Support/<IDE>/User/globalStorage/state.vscdb
    in a platform ternary so Linux uses
        ~/.config/<IDE>/User/globalStorage/state.vscdb

3.  Zed DB path — same idea:
        macOS  ~/Library/Application Support/Zed/db/0-stable/db.sqlite
        Linux  ~/.local/share/zed/db/0-stable/db.sqlite

The home-directory scanner (pjr / equivalent) already works
cross-platform — it just uses os.homedir() + common dir names.

All regex patterns use \\w+ for minified identifiers so they survive
upstream variable-name churn between releases.

Usage: python3 fix_detected_projects_linux.py <path_to_index.js>
"""

import sys
import os
import re


def patch_detected_projects(filepath):
    """Enable Detected Projects on Linux."""

    print("=== Patch: fix_detected_projects_linux ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, "rb") as f:
        content = f.read()

    # ── Idempotency check ─────────────────────────────────────────────
    if b'process.platform!=="linux"' in content and b"[detectedProjects]" in content:
        # Rough check: if we already injected the linux guard, skip
        # (look for the guard specifically near the detectedProjects context)
        idx = content.find(b"[detectedProjects] skipping")
        if idx != -1:
            nearby = content[max(0, idx - 200) : idx]
            if b'process.platform!=="linux"' in nearby:
                print("  [SKIP] Already patched (linux platform guard found)")
                return True

    original_content = content
    all_ok = True

    # ── 1. Platform guard in the detection entry-point ────────────────
    #
    # Before:
    #   if(process.platform!=="darwin")return X.debug(`[detectedProjects] skipping …`),[];
    # After:
    #   if(process.platform!=="darwin"&&process.platform!=="linux")return X.debug(…),[];
    #
    # We anchor on the "[detectedProjects] skipping" string so we only
    # touch this specific platform check, not any other darwin guards.

    pat_guard = (
        rb'(if\(process\.platform!=="darwin")'
        rb"(\)return [\w$]+\.debug\(`\[detectedProjects\] skipping)"
    )

    def repl_guard(m):
        return m.group(1) + b'&&process.platform!=="linux"' + m.group(2)

    content, count = re.subn(pat_guard, repl_guard, content)
    if count > 0:
        print(f"  [OK] Platform guard: {count} match(es)")
    else:
        print("  [FAIL] Platform guard: 0 matches")
        all_ok = False

    # ── 2. VSCode / Cursor state DB path ──────────────────────────────
    #
    # Before:
    #   <path>.join(<os>.homedir(),"Library","Application Support",<dir>,"User","globalStorage","state.vscdb")
    # After (ternary):
    #   (process.platform==="darwin"
    #     ? <path>.join(<os>.homedir(),"Library","Application Support",<dir>,…)
    #     : <path>.join(<os>.homedir(),".config",<dir>,…))
    #
    # <path>, <os>, and <dir> are captured dynamically.

    pat_vscode = (
        rb"(\w+)\.join\((\w+)\.homedir\(\),"
        rb'"Library","Application Support",(\w+),'
        rb'"User","globalStorage","state\.vscdb"\)'
    )

    def repl_vscode(m):
        p = m.group(1).decode()  # path module (e.g. ke)
        o = m.group(2).decode()  # os module   (e.g. Gr)
        d = m.group(3).decode()  # dir param   (e.g. t)
        mac = f'{p}.join({o}.homedir(),"Library","Application Support",{d},"User","globalStorage","state.vscdb")'
        lin = f'{p}.join({o}.homedir(),".config",{d},"User","globalStorage","state.vscdb")'
        return f'(process.platform==="darwin"?{mac}:{lin})'.encode()

    content, count = re.subn(pat_vscode, repl_vscode, content)
    if count > 0:
        print(f"  [OK] VSCode/Cursor DB path: {count} match(es)")
    else:
        print("  [FAIL] VSCode/Cursor DB path: 0 matches")
        all_ok = False

    # ── 3. Zed state DB path ─────────────────────────────────────────
    #
    # Before:
    #   <path>.join(<os>.homedir(),"Library","Application Support","Zed","db","0-stable","db.sqlite")
    # After (ternary):
    #   (process.platform==="darwin"
    #     ? <path>.join(<os>.homedir(),"Library","Application Support","Zed","db","0-stable","db.sqlite")
    #     : <path>.join(<os>.homedir(),".local","share","zed","db","0-stable","db.sqlite"))

    pat_zed = (
        rb"(\w+)\.join\((\w+)\.homedir\(\),"
        rb'"Library","Application Support","Zed",'
        rb'"db","0-stable","db\.sqlite"\)'
    )

    def repl_zed(m):
        p = m.group(1).decode()  # path module
        o = m.group(2).decode()  # os module
        mac = f'{p}.join({o}.homedir(),"Library","Application Support","Zed","db","0-stable","db.sqlite")'
        lin = f'{p}.join({o}.homedir(),".local","share","zed","db","0-stable","db.sqlite")'
        return f'(process.platform==="darwin"?{mac}:{lin})'.encode()

    content, count = re.subn(pat_zed, repl_zed, content)
    if count > 0:
        print(f"  [OK] Zed DB path: {count} match(es)")
    else:
        print("  [FAIL] Zed DB path: 0 matches")
        all_ok = False

    # ── Write back ────────────────────────────────────────────────────
    if content != original_content:
        with open(filepath, "wb") as f:
            f.write(content)
        if all_ok:
            print("  [PASS] Detected Projects patched for Linux")
        else:
            print("  [WARN] Partial patch — some patterns did not match")
        return all_ok
    else:
        print("  [FAIL] No changes made")
        return False


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_detected_projects(sys.argv[1])
    sys.exit(0 if success else 1)
