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
    # Pattern: getDownloadStatus(){return WBe()?Zc.Downloading:IS()?Zc.Ready:Zc.NotDownloaded}
    # Variable names change between versions (WBe→Wme, Zc→Xc, IS→YS)
    vm_status_pattern = rb'getDownloadStatus\(\)\{return (\w+)\(\)\?(\w+)\.Downloading:(\w+)\(\)\?\2\.Ready:\2\.NotDownloaded\}'

    def vm_status_replacement(m):
        enum_name = m.group(2)  # Zc, Xc, etc.
        return (b'getDownloadStatus(){if(process.platform==="linux"){return ' + enum_name +
                b'.NotDownloaded}return ' + m.group(1) + b'()?' + enum_name + b'.Downloading:' +
                m.group(3) + b'()?' + enum_name + b'.Ready:' + enum_name + b'.NotDownloaded}')

    content, count1 = re.subn(vm_status_pattern, vm_status_replacement, content)
    if count1 >= 1:
        print(f"  [OK] ClaudeVM.getDownloadStatus: {count1} match(es)")
        patches_applied += 1
    else:
        print(f"  [WARN] ClaudeVM.getDownloadStatus pattern not found")

    # Patch 2: Modify the ClaudeVM getRunningStatus to always return Offline on Linux
    # Pattern: async getRunningStatus(){return await ty()?qd.Ready:qd.Offline}
    # Variable names change between versions (ty→g0, qd→Qd)
    vm_running_pattern = rb'async getRunningStatus\(\)\{return await (\w+)\(\)\?(\w+)\.Ready:\2\.Offline\}'

    def vm_running_replacement(m):
        enum_name = m.group(2)  # qd, Qd, etc.
        return (b'async getRunningStatus(){if(process.platform==="linux"){return ' + enum_name +
                b'.Offline}return await ' + m.group(1) + b'()?' + enum_name + b'.Ready:' + enum_name + b'.Offline}')

    content, count2 = re.subn(vm_running_pattern, vm_running_replacement, content)
    if count2 >= 1:
        print(f"  [OK] ClaudeVM.getRunningStatus: {count2} match(es)")
        patches_applied += 1
    else:
        print(f"  [WARN] ClaudeVM.getRunningStatus pattern not found")

    # Patch 3: Modify the download function to fail gracefully on Linux
    # Pattern: async download(){try{return await Qhe(),{success:IS()}}
    # Variable names change between versions (Qhe→Hme, IS→YS)
    vm_download_pattern = rb'async download\(\)\{try\{return await (\w+)\(\),\{success:(\w+)\(\)\}'

    def vm_download_replacement(m):
        return (b'async download(){if(process.platform==="linux"){return{success:false,error:"VM download not supported on Linux. Install claude-code from npm: npm install -g @anthropic-ai/claude-code"}}try{return await ' +
                m.group(1) + b'(),{success:' + m.group(2) + b'()}')

    content, count3 = re.subn(vm_download_pattern, vm_download_replacement, content)
    if count3 >= 1:
        print(f"  [OK] ClaudeVM.download: {count3} match(es)")
        patches_applied += 1
    else:
        print(f"  [WARN] ClaudeVM.download pattern not found")

    # Patch 4: Modify startVM to fail gracefully on Linux
    # Pattern: async startVM(e){try{return await Jhe(e),{success:!0}}
    # Variable names change between versions (Jhe→MB)
    vm_start_pattern = rb'async startVM\((\w+)\)\{try\{return await (\w+)\(\1\),\{success:!0\}'

    def vm_start_replacement(m):
        param = m.group(1)   # e.g. r
        func = m.group(2)    # e.g. Sg
        return (b'async startVM(' + param + b'){if(process.platform==="linux"){return{success:false,error:"VM not supported on Linux"}}try{return await ' +
                func + b'(' + param + b'),{success:!0}')

    content, count4 = re.subn(vm_start_pattern, vm_start_replacement, content)
    if count4 >= 1:
        print(f"  [OK] ClaudeVM.startVM: {count4} match(es)")
        patches_applied += 1
    else:
        print(f"  [WARN] ClaudeVM.startVM pattern not found")

    # Patch 5: Add global IPC error handler to suppress known Linux unsupported feature errors
    # Find the app initialization and add error handler
    # Look for XX.app.on("ready" pattern and add error suppression
    # Variable names change between versions (ce→oe)
    app_ready_pattern = rb'(\w+)\.app\.on\("ready",async\(\)=>\{'

    def app_ready_replacement(m):
        electron_var = m.group(1)
        return (electron_var + b'.app.on("ready",async()=>{if(process.platform==="linux"){process.on("uncaughtException",(e)=>{if(e.message&&(e.message.includes("ClaudeVM")||e.message.includes("LocalAgentModeSessions"))){console.log("[LinuxPatch] Suppressing unsupported feature error:",e.message);return}throw e})};')

    content, count5 = re.subn(app_ready_pattern, app_ready_replacement, content, count=1)
    if count5 >= 1:
        print(f"  [OK] App error handler: {count5} match(es)")
        patches_applied += 1
    else:
        # Try alternative pattern (non-async)
        app_ready_pattern_alt = rb'(\w+)\.app\.on\("ready",\(\)=>\{'

        def app_ready_replacement_alt(m):
            electron_var = m.group(1)
            return (electron_var + b'.app.on("ready",()=>{if(process.platform==="linux"){process.on("uncaughtException",(e)=>{if(e.message&&(e.message.includes("ClaudeVM")||e.message.includes("LocalAgentModeSessions"))){console.log("[LinuxPatch] Suppressing unsupported feature error:",e.message);return}throw e})};')

        content, count5_alt = re.subn(app_ready_pattern_alt, app_ready_replacement_alt, content, count=1)
        if count5_alt >= 1:
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
            print(f"  [FAIL] Brace mismatch: {open_braces} open, {close_braces} close")
            return False
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
