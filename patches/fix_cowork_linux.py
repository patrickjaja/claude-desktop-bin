#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Enable Cowork VM features on Linux.

Three-part patch:
A. Extend the TypeScript VM client (vZe) to load on Linux, not just Windows.
   The original code checks Li (process.platform==="win32") to decide whether
   to use the TypeScript VM client or the native Swift module. We extend the
   check to include Linux.
B. Replace Windows Named Pipe path with a Unix domain socket path on Linux.
   The original hardcodes "\\\\.\\pipe\\cowork-vm-service" for Windows.
   On Linux we use $XDG_RUNTIME_DIR/cowork-vm-service.sock (or /tmp fallback).
C. Add Linux to the _i.files bundle configuration so the bundle download
   mechanism works on Linux (reuses win32.x64 file list since the VM images
   are platform-agnostic).

Requires claude-cowork-service daemon running on the host to actually work.
Without the daemon, Cowork UI will show connection errors naturally.

Usage: python3 fix_cowork_linux.py <path_to_index.js>
"""

import sys
import os
import re


def patch_cowork_linux(filepath):
    """Enable Cowork VM client and socket path on Linux."""

    print(f"=== Patch: fix_cowork_linux ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content
    patches_applied = 0

    # Patch A: Extend TypeScript VM client to Linux
    #
    # The VM module loader selects by platform:
    #   Li ? ef={vm:vZe} : ef=(await import("@ant/claude-swift")).default
    # where Li = process.platform==="win32"
    #
    # We change the condition to: (Li||process.platform==="linux")
    # so Linux uses the TypeScript VM client (vZe) instead of trying
    # to load the native Swift module (which doesn't exist on Linux).
    #
    # Capture groups:
    #   1 = Li (condition variable)
    #   2 = ef (assignment target variable)
    #   3 = {vm:vZe} (the VM client object literal)
    #   \2 backreference matches the same variable name in the else branch
    vm_client_pattern = rb'(\w+)\?(\w+)=(\{vm:\w+\}):\2=\(await import\("@ant/claude-swift"\)\)\.default'

    def vm_client_replacement(m):
        li_var = m.group(1)   # Li
        ef_var = m.group(2)   # ef
        vm_obj = m.group(3)   # {vm:vZe}
        return (b'(' + li_var + b'||process.platform==="linux")?' +
                ef_var + b'=' + vm_obj + b':' +
                ef_var + b'=(await import("@ant/claude-swift")).default')

    content, count_a = re.subn(vm_client_pattern, vm_client_replacement, content)
    if count_a >= 1:
        print(f"  [OK] VM client loader: extended to Linux ({count_a} match)")
        patches_applied += 1
    else:
        print(f"  [FAIL] VM client loader: 0 matches")

    # Patch B: Socket path for Linux
    #
    # Currently hardcoded Windows named pipe:
    #   cxe="\\\\.\\pipe\\cowork-vm-service"
    #
    # Replace with platform-conditional:
    #   cxe = process.platform==="linux"
    #     ? (process.env.XDG_RUNTIME_DIR||"/tmp")+"/cowork-vm-service.sock"
    #     : "\\\\.\\pipe\\cowork-vm-service"
    #
    # We use bytes.replace() instead of regex to avoid backslash escaping hell.
    # The pipe path is a unique literal string in the bundle.
    pipe_path = b'"\\\\\\\\.\\\\pipe\\\\cowork-vm-service"'
    pipe_search = b'=' + pipe_path

    if pipe_search in content:
        # Find the variable name before the = sign
        idx = content.index(pipe_search)
        # Walk backwards to find start of variable name
        start = idx - 1
        while start >= 0 and (content[start:start+1].isalnum() or content[start:start+1] in (b'_', b'$')):
            start -= 1
        start += 1
        var_name = content[start:idx]

        replacement = (var_name + b'=process.platform==="linux"'
                       b'?(process.env.XDG_RUNTIME_DIR||"/tmp")+"/cowork-vm-service.sock"'
                       b':' + pipe_path)
        content = content[:start] + replacement + content[idx + len(pipe_search):]
        print(f"  [OK] Socket path: Unix socket on Linux (var={var_name.decode()})")
        patches_applied += 1
    else:
        print(f"  [WARN] Socket path: pipe path not found")

    # Patch C: Add Linux to _i.files bundle config
    #
    # The bundle configuration looks like:
    #   files:{darwin:{arm64:[...]},win32:{arm64:[...],x64:[FILE_LIST]}}
    #
    # We want to add:   ,linux:{x64:FILE_LIST}
    # before the final }} that closes files and the _i object.
    #
    # Strategy:
    # 1. Find the win32 x64 file list by searching for ,x64:[ after win32:{
    # 2. Extract the array contents (balanced bracket matching)
    # 3. Inject ,linux:{x64:[same_list]} after win32's closing }

    # Find the bundle config by its unique structure marker
    win32_marker = b'win32:{'
    win32_idx = content.find(win32_marker)
    if win32_idx >= 0:
        # Find ,x64:[ within the win32 block
        x64_marker = b',x64:['
        x64_search_start = win32_idx
        x64_idx = content.find(x64_marker, x64_search_start)

        if x64_idx >= 0:
            # Extract the x64 array (balanced bracket matching)
            array_start = x64_idx + len(x64_marker) - 1  # Position of '['
            depth = 0
            pos = array_start
            while pos < len(content):
                if content[pos:pos+1] == b'[':
                    depth += 1
                elif content[pos:pos+1] == b']':
                    depth -= 1
                    if depth == 0:
                        break
                pos += 1

            x64_array = content[array_start:pos+1]  # [...full array...]

            # Now find the closing of the win32 block and files block
            # After x64 array ends at pos+1, we expect }}} (close win32, files, _i)
            after_array = pos + 1
            # Skip the win32 closing }
            if content[after_array:after_array+1] == b'}':
                # Insert ,linux:{x64:[...]} right after win32's }
                # before the remaining }} (files close + _i close)
                inject = b',linux:{x64:' + x64_array + b'}'
                content = content[:after_array+1] + inject + content[after_array+1:]
                print(f"  [OK] Bundle config: Linux platform added (x64 array: {len(x64_array)} bytes)")
                patches_applied += 1
            else:
                print(f"  [WARN] Bundle config: unexpected structure after x64 array")
        else:
            print(f"  [WARN] Bundle config: x64 array not found in win32 block")
    else:
        print(f"  [WARN] Bundle config: win32 block not found")

    # Patch D: Fix pathToClaudeCodeExecutable for Linux
    #
    # The Local Agent Mode session manager hardcodes the macOS path:
    #   pathToClaudeCodeExecutable:"/usr/local/bin/claude"
    #
    # On Linux, claude may be at /usr/bin/claude, ~/.local/bin/claude, etc.
    # Replace with a dynamic IIFE that checks known locations on Linux,
    # falling back to bare "claude" for PATH resolution.
    #
    # Also fix the error detection pattern that checks for "/usr/local/bin/claude"
    # in error messages — extend it to also match the Linux paths.

    claude_path_old = b'pathToClaudeCodeExecutable:"/usr/local/bin/claude"'
    claude_path_new = (
        b'pathToClaudeCodeExecutable:'
        b'(()=>{if(process.platform!=="linux")return"/usr/local/bin/claude";'
        b'const fs=require("fs");'
        b'for(const p of["/usr/bin/claude",'
        b'(process.env.HOME||"")+"/.local/bin/claude",'
        b'"/usr/local/bin/claude"])'
        b'if(fs.existsSync(p))return p;'
        b'return"claude"})()'
    )

    if claude_path_old in content:
        content = content.replace(claude_path_old, claude_path_new, 1)
        print(f"  [OK] Claude Code path: dynamic resolution on Linux")
        patches_applied += 1
    else:
        print(f"  [WARN] Claude Code path: pattern not found")

    # Also extend the error detection to recognize Linux paths
    error_detect_old = b't.includes("/usr/local/bin/claude")'
    error_detect_new = b'(t.includes("/usr/local/bin/claude")||t.includes("/usr/bin/claude")||t.includes("/.local/bin/claude"))'

    if error_detect_old in content:
        content = content.replace(error_detect_old, error_detect_new, 1)
        print(f"  [OK] Error detection: extended for Linux paths")
        patches_applied += 1
    else:
        print(f"  [WARN] Error detection: pattern not found")

    # Check results
    if patches_applied == 0:
        print("  [FAIL] No patches could be applied")
        return False

    if content == original_content:
        print("  [WARN] No changes made (patterns may have already been applied)")
        return True

    # Verify our patches didn't introduce a brace imbalance
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

    success = patch_cowork_linux(sys.argv[1])
    sys.exit(0 if success else 1)
