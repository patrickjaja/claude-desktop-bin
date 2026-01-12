#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Patch Claude Desktop to handle ClaudeVM and LocalAgentModeSessions IPC on Linux.

The claude.ai web frontend and popup windows may generate runtime UUIDs for IPC channels
that differ from the hardcoded UUID in the main process handlers. This causes "No handler
registered" errors on Linux.

This patch:
1. Modifies ClaudeVM implementation to return Linux-appropriate values immediately
2. Ensures graceful degradation when VM features are not available
3. Suppresses VM-related functionality on Linux since it's not supported

Usage: python3 fix_vm_session_handlers.py <path_to_index.js>
"""

import sys
import os
import re


def patch_vm_session_handlers(filepath):
    """Add Linux-specific handling for ClaudeVM and LocalAgentModeSessions."""

    print(f"=== Patch: fix_vm_session_handlers ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content
    patches_applied = 0

    # Patch 1: Modify the ClaudeVM getDownloadStatus to always return NotDownloaded on Linux
    # This prevents the UI from trying to download the VM
    old_vm_status = b'getDownloadStatus(){return WBe()?Zc.Downloading:IS()?Zc.Ready:Zc.NotDownloaded}'
    new_vm_status = b'getDownloadStatus(){if(process.platform==="linux"){return Zc.NotDownloaded}return WBe()?Zc.Downloading:IS()?Zc.Ready:Zc.NotDownloaded}'

    count1 = content.count(old_vm_status)
    if count1 >= 1:
        content = content.replace(old_vm_status, new_vm_status)
        print(f"  [OK] ClaudeVM.getDownloadStatus: {count1} match(es)")
        patches_applied += 1
    else:
        print(f"  [WARN] ClaudeVM.getDownloadStatus pattern not found")

    # Patch 2: Modify the ClaudeVM getRunningStatus to always return Offline on Linux
    old_vm_running = b'async getRunningStatus(){return await ty()?qd.Ready:qd.Offline}'
    new_vm_running = b'async getRunningStatus(){if(process.platform==="linux"){return qd.Offline}return await ty()?qd.Ready:qd.Offline}'

    count2 = content.count(old_vm_running)
    if count2 >= 1:
        content = content.replace(old_vm_running, new_vm_running)
        print(f"  [OK] ClaudeVM.getRunningStatus: {count2} match(es)")
        patches_applied += 1
    else:
        print(f"  [WARN] ClaudeVM.getRunningStatus pattern not found")

    # Patch 3: Modify the download function to fail gracefully on Linux
    old_vm_download = b'async download(){try{return await Qhe(),{success:IS()}}'
    new_vm_download = b'async download(){if(process.platform==="linux"){return{success:false,error:"VM download not supported on Linux. Install claude-code from npm: npm install -g @anthropic-ai/claude-code"}}try{return await Qhe(),{success:IS()}}'

    count3 = content.count(old_vm_download)
    if count3 >= 1:
        content = content.replace(old_vm_download, new_vm_download)
        print(f"  [OK] ClaudeVM.download: {count3} match(es)")
        patches_applied += 1
    else:
        print(f"  [WARN] ClaudeVM.download pattern not found")

    # Patch 4: Modify startVM to fail gracefully on Linux
    old_vm_start = b'async startVM(e){try{return await Jhe(e),{success:!0}}'
    new_vm_start = b'async startVM(e){if(process.platform==="linux"){return{success:false,error:"VM not supported on Linux"}}try{return await Jhe(e),{success:!0}}'

    count4 = content.count(old_vm_start)
    if count4 >= 1:
        content = content.replace(old_vm_start, new_vm_start)
        print(f"  [OK] ClaudeVM.startVM: {count4} match(es)")
        patches_applied += 1
    else:
        print(f"  [WARN] ClaudeVM.startVM pattern not found")

    # Patch 5: Add global IPC error handler to suppress known Linux unsupported feature errors
    # Find the app initialization and add error handler
    # Look for ce.app.on pattern and add error suppression
    old_app_ready = b"ce.app.on(\"ready\",async()=>{"
    new_app_ready = b"ce.app.on(\"ready\",async()=>{if(process.platform===\"linux\"){process.on(\"uncaughtException\",(e)=>{if(e.message&&(e.message.includes(\"ClaudeVM\")||e.message.includes(\"LocalAgentModeSessions\"))){console.log(\"[LinuxPatch] Suppressing unsupported feature error:\",e.message);return}throw e})};"

    count5 = content.count(old_app_ready)
    if count5 >= 1:
        content = content.replace(old_app_ready, new_app_ready)
        print(f"  [OK] App error handler: {count5} match(es)")
        patches_applied += 1
    else:
        # Try alternative pattern
        old_app_ready_alt = b'ce.app.on("ready",()=>{'
        new_app_ready_alt = b'ce.app.on("ready",()=>{if(process.platform==="linux"){process.on("uncaughtException",(e)=>{if(e.message&&(e.message.includes("ClaudeVM")||e.message.includes("LocalAgentModeSessions"))){console.log("[LinuxPatch] Suppressing unsupported feature error:",e.message);return}throw e})};'

        count5_alt = content.count(old_app_ready_alt)
        if count5_alt >= 1:
            content = content.replace(old_app_ready_alt, new_app_ready_alt)
            print(f"  [OK] App error handler (alt): {count5_alt} match(es)")
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

    # Verify syntax (basic check)
    try:
        # Check for balanced braces (very basic validation)
        open_braces = content.count(b'{')
        close_braces = content.count(b'}')
        if open_braces != close_braces:
            print(f"  [WARN] Brace mismatch: {open_braces} open, {close_braces} close")
    except:
        pass

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
