#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Fix cowork sandbox/VM references for Linux.

On macOS/Windows, cowork runs inside a lightweight Linux VM (Ubuntu 22) that
provides an isolated sandbox. On Linux with the native Go backend
(claude-cowork-service), there is NO VM — Claude Code runs directly on the
host system. The upstream system prompts and tool descriptions falsely tell
the model it's in a sandbox, causing it to:

  - Claim it runs in "an isolated Linux sandbox (Ubuntu 22)"
  - Believe files it creates don't exist on the user's machine
  - Think it has restricted filesystem access

What we patch:
  A) Bash tool description: "isolated Linux workspace" → "host Linux system"
  B) Cowork identity prompt: "lightweight Linux VM" → "directly on the host"
  C) Computer use explanation: "lightweight Linux VM (Ubuntu 22)" → host
  D) System prompt: "isolated Linux environment" → "host Linux system" (3x)

Note: The "Separate filesystems" computer-use paragraph (sandbox vs real
computer) is already patched by fix_computer_use_linux.py sub-patch 14a.

Usage: python3 fix_cowork_sandbox_refs.py <path_to_index.js>
"""

import sys
import os
import re


EXPECTED_PATCHES = 4


def patch_sandbox_refs(filepath):
    """Replace sandbox/VM references with accurate Linux descriptions."""

    print("=== Patch: fix_cowork_sandbox_refs ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, "rb") as f:
        content = f.read()

    original_content = content
    patches_applied = 0

    # ── Patch A: Bash tool description ───────────────────────────────
    #
    # Upstream (Edn function) constructs the description via concat:
    #   "Run a shell command in the session's isolated Linux workspace.
    #    Your connected folders are mounted under /sessions/"
    #    + t.vmProcessName +
    #    "/mnt/ — the request_cowork_directory tool shows the exact
    #    mount path for each folder. Each bash call is independent
    #    (no cwd/env carryover). Use absolute paths. The workspace
    #    boots in the background and may not be ready on the first
    #    call; if so, you'll see 'Workspace still starting' — wait a
    #    few seconds and retry."
    #
    # On Linux there is no VM, no /sessions/ mount paths, no boot.
    # Replace BOTH string halves with a single clean description.
    # The dynamic concat (+ t.vmProcessName +) is kept but made inert.

    already_a = b"There is no VM or sandbox" in content and b"isolated Linux workspace" not in content
    if already_a:
        print("  [OK] A bash tool description: already patched (skipped)")
        patches_applied += 1
    else:
        # Match: "Run a shell command in the session's isolated Linux workspace. ..."
        #        + <expr> +
        #        "/mnt/ — ... retry."
        # Replace both halves, keeping the + <expr> + syntax intact.
        pattern_a = (
            rb'"Run a shell command in the session\'s isolated Linux workspace\.'
            rb'[^"]*?/sessions/"'  # first half up to closing "
            rb"(\+[\w$.]+\+)"  # capture the dynamic concat expression
            rb'"/mnt/[^"]*?"'  # second half
        )

        def repl_a(m):
            return (
                b'"Run a shell command on the host Linux system.'
                b" There is no VM or sandbox \\u2014 commands execute directly"
                b" on the user\\u2019s computer."
                b" Each bash call is independent (no cwd/env carryover)."
                b' Use absolute paths."'
                + m.group(1)  # keep the dynamic concat expression
                + b'"unused"'  # make the second half inert
            )

        content, count = re.subn(pattern_a, repl_a, content, count=1)
        if count == 1:
            print("  [OK] A bash tool description: replaced with host-aware text")
            patches_applied += 1
        else:
            print("  [FAIL] A bash tool description: pattern not found")

    # ── Patch B: Cowork identity system prompt ───────────────────────
    #
    # Upstream: "Claude runs in a lightweight Linux VM on the user's
    #           computer, which provides a secure sandbox for executing
    #           code while allowing controlled access to a workspace
    #           folder."
    #
    # On Linux: Claude runs directly on the host, no VM, no sandbox.

    old_b = b"Claude runs in a lightweight Linux VM on the user's computer, which provides a secure sandbox for executing code while allowing controlled access to a workspace folder."
    new_b = b"Claude runs directly on the user's Linux computer with full access to the local filesystem and installed tools. There is no VM or sandbox."

    already_b = b"Claude runs directly on the user's Linux computer with full" in content
    if already_b:
        print("  [OK] B cowork identity prompt: already patched (skipped)")
        patches_applied += 1
    else:
        count = content.count(old_b)
        if count == 1:
            content = content.replace(old_b, new_b, 1)
            print("  [OK] B cowork identity prompt: replaced with Linux-accurate text")
            patches_applied += 1
        else:
            print(f"  [FAIL] B cowork identity prompt: expected 1 occurrence, found {count}")

    # ── Patch C: Computer use high-level explanation ─────────────────
    #
    # Upstream: "Claude runs in a lightweight Linux VM (Ubuntu 22) on
    #           the user's computer. This VM provides a secure sandbox
    #           for executing code while allowing controlled access to
    #           user files."
    #
    # On Linux: same machine, no VM.

    old_c = b"Claude runs in a lightweight Linux VM (Ubuntu 22) on the user's computer. This VM provides a secure sandbox for executing code while allowing controlled access to user files."
    new_c = b"Claude runs directly on the user's Linux computer. Commands execute on the host system with full access to local files and tools. There is no VM or sandbox."

    already_c = b"Commands execute on the host system with full access to local" in content
    if already_c:
        print("  [OK] C computer use explanation: already patched (skipped)")
        patches_applied += 1
    else:
        count = content.count(old_c)
        if count == 1:
            content = content.replace(old_c, new_c, 1)
            print("  [OK] C computer use explanation: replaced with Linux-accurate text")
            patches_applied += 1
        else:
            print(f"  [FAIL] C computer use explanation: expected 1 occurrence, found {count}")

    # ── Patch D: "isolated Linux environment" → "host Linux system" ──
    #
    # 3 occurrences:
    #   1) Error: "Workspace still starting. The isolated Linux environment
    #              is booting in the background"
    #   2) Error: "Workspace unavailable. The isolated Linux environment
    #              failed to start."
    #   3) System prompt: "Shell commands ... run in an isolated Linux
    #              environment."
    #
    # Replace all 3. On Linux the workspace isn't "booting" — it starts
    # Claude Code directly. The errors may still fire if the cowork
    # service is slow, but the description should be accurate.

    # Two forms: "The isolated Linux environment" (error messages) and
    # "an isolated Linux environment" (system prompt — article must change)
    old_d1 = b"The isolated Linux environment"
    new_d1 = b"The host Linux environment"
    old_d2 = b"an isolated Linux environment"
    new_d2 = b"the host Linux environment"

    already_d = content.count(old_d1) == 0 and content.count(old_d2) == 0 and b"host Linux environment" in content
    if already_d:
        print("  [OK] D isolated Linux environment: already patched (skipped)")
        patches_applied += 1
    else:
        count_d1 = content.count(old_d1)
        count_d2 = content.count(old_d2)
        total = count_d1 + count_d2
        if total >= 1:
            content = content.replace(old_d1, new_d1)
            content = content.replace(old_d2, new_d2)
            print(f"  [OK] D isolated Linux environment: replaced {total} occurrences ({count_d1} 'The' + {count_d2} 'an')")
            patches_applied += 1
        else:
            print("  [FAIL] D isolated Linux environment: pattern not found")

    if patches_applied < EXPECTED_PATCHES:
        print(f"  [FAIL] Only {patches_applied}/{EXPECTED_PATCHES} patches applied")
        return False

    if content != original_content:
        with open(filepath, "wb") as f:
            f.write(content)
        print(f"  [PASS] All {patches_applied} sandbox/VM references fixed for Linux")
        return True
    else:
        print("  [OK] Already patched, no changes needed")
        return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_sandbox_refs(sys.argv[1])
    sys.exit(0 if success else 1)
