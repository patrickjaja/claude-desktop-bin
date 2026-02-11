#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Add safety-net error handler for ClaudeVM and LocalAgentModeSessions IPC on Linux.

With the Cowork Linux support (fix_cowork_linux.py), the TypeScript VM client
now runs on Linux and talks to the cowork-svc-linux daemon via Unix socket.
The previous Linux stubs (getDownloadStatus, getRunningStatus, download, startVM)
are no longer needed — those methods now call through to the real VM client which
communicates with the daemon.

This patch only keeps the global uncaught exception handler as a safety net to
suppress any unexpected "ClaudeVM" or "LocalAgentModeSessions" errors that might
occur if the daemon is not running or connection fails unexpectedly.

Usage: python3 fix_vm_session_handlers.py <path_to_index.js>
"""

import sys
import os
import re


def patch_vm_session_handlers(filepath):
    """Add global error handler for ClaudeVM/LocalAgentModeSessions as safety net."""

    print(f"=== Patch: fix_vm_session_handlers ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content
    patches_applied = 0

    # Global IPC error handler to suppress known Linux unsupported feature errors
    # Find the app initialization and add error handler
    # Look for XX.app.on("ready" pattern and add error suppression
    # Variable names change between versions (ce→oe)
    app_ready_pattern = rb'(\w+)\.app\.on\("ready",async\(\)=>\{'

    def app_ready_replacement(m):
        electron_var = m.group(1)
        return (electron_var + b'.app.on("ready",async()=>{if(process.platform==="linux"){process.on("uncaughtException",(e)=>{if(e.message&&(e.message.includes("ClaudeVM")||e.message.includes("LocalAgentModeSessions"))){console.log("[LinuxPatch] Suppressing unsupported feature error:",e.message);return}throw e})};')

    content, count = re.subn(app_ready_pattern, app_ready_replacement, content, count=1)
    if count >= 1:
        print(f"  [OK] App error handler: {count} match(es)")
        patches_applied += 1
    else:
        # Try alternative pattern (non-async)
        app_ready_pattern_alt = rb'(\w+)\.app\.on\("ready",\(\)=>\{'

        def app_ready_replacement_alt(m):
            electron_var = m.group(1)
            return (electron_var + b'.app.on("ready",()=>{if(process.platform==="linux"){process.on("uncaughtException",(e)=>{if(e.message&&(e.message.includes("ClaudeVM")||e.message.includes("LocalAgentModeSessions"))){console.log("[LinuxPatch] Suppressing unsupported feature error:",e.message);return}throw e})};')

        content, count_alt = re.subn(app_ready_pattern_alt, app_ready_replacement_alt, content, count=1)
        if count_alt >= 1:
            print(f"  [OK] App error handler (alt): {count_alt} match(es)")
            patches_applied += 1
        else:
            print(f"  [WARN] App ready pattern not found")

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

    success = patch_vm_session_handlers(sys.argv[1])
    sys.exit(0 if success else 1)
