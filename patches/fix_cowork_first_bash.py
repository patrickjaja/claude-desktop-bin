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
    # Upstream oneshot spawn function:
    #   FUNC1(),await FUNC2();const n=await FUNC3();
    #
    # FUNC2() triggers the events socket opener (JVt/similar), which calls
    # createConnection() — async. The events socket variable (nE/similar)
    # is set in the "connect" callback. If a command is spawned before
    # the socket connects, stdout/exit events are missed.
    #
    # Fix: find the events socket variable by anchoring on subscribeEvents,
    # then inject a poll-wait between await FUNC2() and const n=.

    import re as _re_a

    # Step 1: find the events socket variable name
    # Pattern: function FUNC(){if(VAR)return;...createConnection...subscribeEvents
    ev_sock_match = _re_a.search(rb"function ([\w$]+)\(\)\{if\(([\w$]+)\)return;const [\w$]+=[\w$]+\.createConnection", content)
    if not ev_sock_match:
        print("  [FAIL] A events socket wait: cannot find events socket function")
    else:
        ev_var = ev_sock_match.group(2)  # e.g. nE
        ev_var_str = ev_var.decode("utf-8")

        # Step 2: match the spawn preamble using regex
        # Pattern: FUNC(),await FUNC();const VAR=await FUNC();if(!VAR)throw new Error("VM
        spawn_pattern = (
            rb"([\w$]+\(\),await [\w$]+\(\))"
            rb'(;const ([\w$]+)=await [\w$]+\(\);if\(!\3\)throw new Error\("VM is not available)'
        )

        already_a = b"_cdb_evsock_wait" in content
        if already_a:
            print("  [OK] A events socket wait: already patched (skipped)")
            patches_applied += 1
        else:
            spawn_match = _re_a.search(spawn_pattern, content)
            if spawn_match:
                # Inject poll-wait for the events socket variable between the two parts
                wait_code = (
                    b";/* _cdb_evsock_wait */"
                    b"if(typeof " + ev_var + b'==="undefined"||!' + ev_var + b")"
                    b"await new Promise(function(_r){"
                    b"var _c=0,_iv=setInterval(function(){"
                    b"if((typeof " + ev_var + b'!=="undefined"&&' + ev_var + b")||++_c>200){clearInterval(_iv);_r()}"
                    b"},10)})"
                )

                old_full = spawn_match.group(0)
                new_full = spawn_match.group(1) + wait_code + spawn_match.group(2)
                content = content.replace(old_full, new_full, 1)
                print(f"  [OK] A events socket wait: injected {ev_var_str} poll-wait before spawn")
                patches_applied += 1
            else:
                print("  [FAIL] A events socket wait: spawn pattern not found")

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
