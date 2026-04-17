#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Rewrite cowork sandbox/VM references for runtime-selected backend.

Upstream tool descriptions + system prompts tell the model it runs in a
"lightweight Linux VM (Ubuntu 22)" or "isolated Linux environment". That is
accurate when the kvm backend is running but wrong on native — the native
backend executes Claude Code directly on the host.

Each patch wraps the affected text in a JS ternary keyed off
`globalThis.__coworkKvmMode`, which is set by `fix_cowork_linux.py`'s
preamble based on `COWORK_VM_BACKEND` / socket auto-detect:

    globalThis.__coworkKvmMode ? "<original VM-accurate text>"
                               : "<host-accurate rewrite>"

The injection style depends on the JS string-literal kind that surrounds
the target text:

  "…target…"        → close the dquote, concat a ternary, reopen:
                      "…" + (globalThis.__coworkKvmMode?"orig":"new") + "…"
  `…target…`        → template interpolation:
                      `…${globalThis.__coworkKvmMode?"orig":"new"}…`

Patches always run on clean, freshly-extracted bundles — no "already
patched" fast path; a missing anchor is a hard failure.

Patches:
  A) Bash tool description: "isolated Linux workspace" vs "host Linux system"
  B) Cowork identity prompt: "lightweight Linux VM" vs "directly on the host"
  C) Computer use explanation: "lightweight Linux VM (Ubuntu 22)" vs host
  D) System prompt + error messages: "isolated Linux environment" vs "host"

Usage: python3 fix_cowork_sandbox_refs.py <path_to_index.js>
"""

import sys
import os
import re


EXPECTED_PATCHES = 4


def _classify_context(content: bytes, pos: int) -> str:
    """Return 'backtick' or 'dquote' — whichever delimiter is nearest
    before `pos` is the enclosing literal kind. Used to pick the right
    injection style."""
    last_bt = content.rfind(b"`", 0, pos)
    last_dq = content.rfind(b'"', 0, pos)
    if last_bt > last_dq:
        return "backtick"
    return "dquote"


def _inject_ternary(context: str, orig: bytes, new: bytes) -> bytes:
    """Produce the bytes to replace `orig` with so the bundle evaluates to
    either `orig` or `new` at runtime depending on globalThis.__coworkKvmMode.

    Dquote context: `"…" + ternary + "…"` style.
    Backtick context: `…${ternary}…` style (raw `${}` — no extra quotes).
    """
    ternary = b'globalThis.__coworkKvmMode?"' + orig + b'":"' + new + b'"'
    if context == "backtick":
        return b"${" + ternary + b"}"
    return b'"+(' + ternary + b')+"'


def _replace_substring_context_aware(content: bytes, orig: bytes, new: bytes) -> tuple[bytes, int]:
    """Replace every occurrence of `orig` in `content` with a runtime
    ternary whose form depends on the enclosing string-literal kind.

    Scans left-to-right so each replacement's context is computed against
    the still-pristine prefix — fresh replacements don't confuse later
    context lookups (a backtick/dquote we insert lives downstream only)."""
    result = bytearray()
    cursor = 0
    count = 0
    while True:
        pos = content.find(orig, cursor)
        if pos < 0:
            result.extend(content[cursor:])
            break
        context = _classify_context(content, pos)
        result.extend(content[cursor:pos])
        result.extend(_inject_ternary(context, orig, new))
        cursor = pos + len(orig)
        count += 1
    return bytes(result), count


def patch_sandbox_refs(filepath):
    """Rewrite sandbox/VM references with runtime-selected text."""

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
    # Upstream: "Run a shell command in the session's isolated Linux
    #           workspace. Your connected folders are mounted under
    #           /sessions/" + t.vmProcessName + "/mnt/ — …"
    #
    # Both halves are plain "…" literals so use dquote-style injection
    # directly: wrap each half in a ternary. The dynamic concat (+expr+)
    # stays intact.
    pattern_a = re.compile(
        rb'("Run a shell command in the session\'s isolated Linux workspace\.'
        rb'[^"]*?/sessions/")'     # first half literal
        rb"(\+[\w$.]+\+)"          # dynamic concat (+ t.vmProcessName +)
        rb'("/mnt/[^"]*?")'        # second half literal
    )

    native_half1 = (
        b'"Run a shell command on the host Linux system.'
        b" There is no VM or sandbox \\u2014 commands execute directly"
        b" on the user\\u2019s computer."
        b" Each bash call is independent (no cwd/env carryover)."
        b' Use absolute paths."'
    )
    native_half2 = b'""'

    def repl_a(m):
        orig_half1 = m.group(1)
        concat = m.group(2)
        orig_half2 = m.group(3)
        return (
            b"(globalThis.__coworkKvmMode?" + orig_half1 + b":" + native_half1 + b")"
            + concat
            + b"(globalThis.__coworkKvmMode?" + orig_half2 + b":" + native_half2 + b")"
        )

    content, count_a = pattern_a.subn(repl_a, content, count=1)
    if count_a == 1:
        print("  [OK] A bash tool description: wrapped in runtime ternary")
        patches_applied += 1
    else:
        print("  [FAIL] A bash tool description: pattern not found")

    # ── Patch B: Cowork identity system prompt ───────────────────────
    # Embedded in a template literal (NMr = `…`) so injection uses `${…}`.
    orig_b = b"Claude runs in a lightweight Linux VM on the user's computer, which provides a secure sandbox for executing code while allowing controlled access to a workspace folder."
    new_b = b"Claude runs directly on the user's Linux computer with full access to the local filesystem and installed tools. There is no VM or sandbox."

    content, count_b = _replace_substring_context_aware(content, orig_b, new_b)
    if count_b >= 1:
        print(f"  [OK] B cowork identity prompt: wrapped {count_b} occurrence(s)")
        patches_applied += 1
    else:
        print("  [FAIL] B cowork identity prompt: pattern not found")

    # ── Patch C: Computer use high-level explanation ─────────────────
    orig_c = b"Claude runs in a lightweight Linux VM (Ubuntu 22) on the user's computer. This VM provides a secure sandbox for executing code while allowing controlled access to user files."
    new_c = b"Claude runs directly on the user's Linux computer. Commands execute on the host system with full access to local files and tools. There is no VM or sandbox."

    content, count_c = _replace_substring_context_aware(content, orig_c, new_c)
    if count_c >= 1:
        print(f"  [OK] C computer use explanation: wrapped {count_c} occurrence(s)")
        patches_applied += 1
    else:
        print("  [FAIL] C computer use explanation: pattern not found")

    # ── Patch D: "isolated Linux environment" variants ──────────────
    #
    # Two substring forms; each can appear in either a "…" string literal
    # (error messages) or a `…` template literal (system prompt). The
    # context-aware helper picks the right injection style per occurrence.
    variants = [
        (b"The isolated Linux environment", b"The host Linux environment"),
        (b"an isolated Linux environment", b"the host Linux environment"),
    ]

    total_d = 0
    for orig_sub, new_sub in variants:
        content, n = _replace_substring_context_aware(content, orig_sub, new_sub)
        total_d += n

    if total_d >= 1:
        print(f"  [OK] D isolated Linux environment: wrapped {total_d} occurrence(s)")
        patches_applied += 1
    else:
        print("  [FAIL] D isolated Linux environment: pattern not found")

    # ── Checks ───────────────────────────────────────────────────────
    if patches_applied < EXPECTED_PATCHES:
        print(f"  [FAIL] Only {patches_applied}/{EXPECTED_PATCHES} patches applied")
        return False

    original_delta = original_content.count(b"{") - original_content.count(b"}")
    patched_delta = content.count(b"{") - content.count(b"}")
    if original_delta != patched_delta:
        diff = patched_delta - original_delta
        print(f"  [FAIL] Patch introduced brace imbalance: {diff:+d} unmatched braces")
        return False

    with open(filepath, "wb") as f:
        f.write(content)
    print(f"  [PASS] All {patches_applied} sandbox/VM references wrapped for runtime selection")
    return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_sandbox_refs(sys.argv[1])
    sys.exit(0 if success else 1)
