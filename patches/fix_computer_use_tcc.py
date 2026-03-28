#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Register stub IPC handlers for ComputerUseTcc on Linux.

On macOS, the @ant/claude-swift native module registers IPC handlers for
ComputerUseTcc (accessibility, screen recording permissions). On Linux,
neither claude-swift nor any handler is loaded, causing repeated errors:

  Error: No handler registered for '..._ComputerUseTcc_$_getState'

This patch registers no-op handlers that return sensible defaults:
- getState: returns all permissions as "not_applicable" (Linux doesn't use TCC)
- requestAccessibility/requestScreenRecording: no-op
- openSystemSettings: no-op
- getCurrentSessionGrants: empty array
- revokeGrant: no-op

Usage: python3 fix_computer_use_tcc.py <path_to_index.js>
"""

import sys
import os
import re


def build_stub_handlers_js(eipc_prefix):
    """Build the stub handler JS code with the given eipc prefix."""
    return (
        'if(process.platform==="linux"){'
        'const _ipc=require("electron").ipcMain;'
        f'const _P="{eipc_prefix}";'
        '_ipc.handle(_P+"getState",()=>({accessibility:"not_applicable",screenRecording:"not_applicable"}));'
        '_ipc.handle(_P+"requestAccessibility",()=>{});'
        '_ipc.handle(_P+"requestScreenRecording",()=>{});'
        '_ipc.handle(_P+"openSystemSettings",()=>{});'
        '_ipc.handle(_P+"getCurrentSessionGrants",()=>[]);'
        '_ipc.handle(_P+"revokeGrant",()=>{});'
        "}"
    )


def extract_eipc_uuid(content):
    """Extract the eipc UUID from the file content dynamically."""
    # Look for $eipc_message$_<UUID> pattern
    m = re.search(
        rb"\$eipc_message\$_([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})",
        content,
    )
    if m:
        return m.group(1).decode("utf-8")
    return None


def patch_computer_use_tcc(filepath):
    """Register ComputerUseTcc stub IPC handlers on Linux."""

    print("=== Patch: fix_computer_use_tcc ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, "rb") as f:
        content = f.read()

    original_content = content

    # Dynamically extract the eipc UUID from the file
    uuid = extract_eipc_uuid(content)
    if not uuid:
        # Fallback: check mainView.js in the same directory
        mainview = os.path.join(os.path.dirname(filepath), "mainView.js")
        if os.path.exists(mainview):
            with open(mainview, "rb") as f:
                uuid = extract_eipc_uuid(f.read())
    if not uuid:
        print("  [FAIL] Could not extract eipc UUID from source files")
        return False

    eipc_prefix = f"$eipc_message$_{uuid}_$_claude.web_$_ComputerUseTcc_$_"
    print(f"  [OK] Extracted eipc UUID: {uuid}")

    stub_js = build_stub_handlers_js(eipc_prefix)

    # Inject after app.on("ready", async () => { ...first check...
    # We look for the app.on("ready" handler and inject right after the opening
    pattern = rb'(app\.on\("ready",async\(\)=>\{)'

    replacement = rb"\1" + stub_js.encode("utf-8")

    content, count = re.subn(pattern, replacement, content, count=1)
    if count >= 1:
        print(f"  [OK] ComputerUseTcc stub handlers: injected ({count} match)")
    else:
        print('  [FAIL] app.on("ready") pattern: 0 matches')
        return False

    if content != original_content:
        with open(filepath, "wb") as f:
            f.write(content)
        print("  [PASS] ComputerUseTcc handlers registered for Linux")
        return True
    else:
        print("  [WARN] No changes made")
        return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_computer_use_tcc(sys.argv[1])
    sys.exit(0 if success else 1)
