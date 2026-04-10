#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Fix first bash command returning empty output in Cowork sessions.

Root cause: The events socket (yUt) and the RPC socket (hu/FVr) are separate
connections to the cowork service. qTe() calls Sq() which triggers yUt() to
open the events socket, but yUt() returns immediately — the socket.connect()
is async. Then qTe() immediately sends the spawn command via the RPC socket,
which is already connected. On Linux with the native Go backend, the command
executes in <1ms, stdout/exit events fire before the events socket has
finished connecting and subscribing. Result: first command returns "(no output)".

On macOS/Windows this doesn't happen because the VM takes seconds to boot,
giving the events socket time to connect. On Linux the backend is instant.

Fix: After `await Sq()`, poll-wait for the events socket variable (mA) to be
set (max 2 seconds). This ensures the subscribeEvents handshake is complete
before any spawn command is sent.

Usage: python3 fix_cowork_first_bash.py <path_to_index.js>
"""

import sys
import os


EXPECTED_PATCHES = 1


def patch_first_bash(filepath):
    """Add events socket readiness wait before first bash spawn."""

    print("=== Patch: fix_cowork_first_bash ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, "rb") as f:
        content = f.read()

    original_content = content
    patches_applied = 0

    # ── Patch A: Wait for events socket before spawn ─────────────────
    #
    # Upstream qTe():
    #   ZVt(),await Sq();const n=await Ts();
    #
    # After Sq() completes, the events socket (yUt) has been OPENED but
    # may not be CONNECTED. The variable mA is set in the connect callback.
    # We inject a poll-wait for mA between Sq() and Ts().

    old_a = b"ZVt(),await Sq();const n=await Ts()"

    # Poll mA every 10ms, max 200 iterations (2 seconds).
    # On a healthy system this resolves in one tick (<10ms).
    new_a = (
        b"ZVt(),await Sq();"
        b'if(typeof mA==="undefined"||!mA)'
        b"await new Promise(function(_r){"
        b"var _c=0,_iv=setInterval(function(){"
        b'if((typeof mA!=="undefined"&&mA)||++_c>200){clearInterval(_iv);_r()}'
        b"},10)})"
        b";const n=await Ts()"
    )

    already_a = b'if(typeof mA==="undefined"||!mA)await new Promise' in content
    if already_a:
        print("  [OK] A events socket wait: already patched (skipped)")
        patches_applied += 1
    else:
        count = content.count(old_a)
        if count == 1:
            content = content.replace(old_a, new_a, 1)
            print("  [OK] A events socket wait: injected mA poll-wait before spawn")
            patches_applied += 1
        else:
            print(f"  [FAIL] A events socket wait: expected 1 occurrence, found {count}")

    if patches_applied < EXPECTED_PATCHES:
        print(f"  [FAIL] Only {patches_applied}/{EXPECTED_PATCHES} patches applied")
        return False

    if content != original_content:
        with open(filepath, "wb") as f:
            f.write(content)
        print("  [PASS] First bash command race condition fixed")
        return True
    else:
        print("  [OK] Already patched, no changes needed")
        return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_first_bash(sys.argv[1])
    sys.exit(0 if success else 1)
