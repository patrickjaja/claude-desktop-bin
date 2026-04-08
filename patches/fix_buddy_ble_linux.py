#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Enable Hardware Buddy (Nibblet BLE device) on Linux.

The Buddy feature communicates with a Nibblet (M5StickC Plus) over BLE using
the Nordic UART Service (NUS). The BLE transport runs entirely through Web
Bluetooth in Electron's renderer — no native code involved. On macOS it works
natively; on Linux Electron uses BlueZ/D-Bus (requires bluez package).

Two issues on Linux:
  A) GrowthBook flag 2358734848 gates the feature — force it on.
  B) Race condition: the buddy_window renderer calls reportState("ready")
     during preload, before the async BLE bridge init completes and
     setImplementation() registers the real handlers. Register early stubs
     at app.on("ready") so the renderer doesn't hit missing handlers.
     The real setImplementation() calls removeHandler() before handle(),
     so the stubs are cleanly replaced once the bridge initializes.

Prerequisites (Linux): bluez package for BLE support in Chromium/Electron.

Usage: python3 fix_buddy_ble_linux.py <path_to_index.js>
"""

import sys
import os
import re


EXPECTED_PATCHES = 2


def extract_eipc_uuid(content):
    """Extract the eipc UUID from the file content."""
    m = re.search(
        rb"\$eipc_message\$_([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})",
        content,
    )
    if m:
        return m.group(1).decode("utf-8")
    return None


def build_early_stubs_js(eipc_prefix):
    """Early no-op IPC handlers replaced when setImplementation() runs."""
    buddy = eipc_prefix + "claude.buddy_$_Buddy_$_"
    ble = eipc_prefix + "claude.buddy_$_BuddyBleTransport_$_"

    return (
        'if(process.platform==="linux"){'
        'const _bi=require("electron").ipcMain;'
        # BuddyBleTransport — called by renderer preload before bridge init
        f'_bi.handle("{ble}reportState",()=>{{}});'
        f'_bi.handle("{ble}rx",()=>{{}});'
        f'_bi.handle("{ble}log",()=>{{}});'
        # Buddy — called by buddy_window renderer
        f'_bi.handle("{buddy}status",()=>({{connected:false,error:null,paired:false}}));'
        f'_bi.handle("{buddy}deviceStatus",()=>null);'
        f'_bi.handle("{buddy}setName",()=>null);'
        f'_bi.handle("{buddy}pairDevice",()=>"");'
        f'_bi.handle("{buddy}scanDevices",()=>[]);'
        f'_bi.handle("{buddy}pickDevice",()=>false);'
        f'_bi.handle("{buddy}cancelScan",()=>{{}});'
        f'_bi.handle("{buddy}forgetDevice",()=>{{}});'
        f'_bi.handle("{buddy}pickFolder",()=>null);'
        f'_bi.handle("{buddy}preview",()=>null);'
        f'_bi.handle("{buddy}install",()=>{{}});'
        "}"
    )


def patch_buddy_ble(filepath):
    """Enable Buddy BLE on Linux: force flag + early stubs."""

    print("=== Patch: fix_buddy_ble_linux ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, "rb") as f:
        content = f.read()

    original_content = content
    patches_applied = 0

    if b"BuddyBleTransport" not in content:
        print("  [SKIP] No BuddyBleTransport references (feature not present)")
        return True

    # ── Patch A: Force the Buddy feature flag on Linux ────────────────
    #
    # Upstream:  const <ID>="2358734848",<FN>=()=><READER>(<ID>)
    # Patched:   ...,<FN>=()=>process.platform==="linux"||<READER>(<ID>)

    already_a = b'process.platform==="linux"||' in content and b'"2358734848"' in content
    if already_a:
        print("  [OK] Buddy flag: already patched (skipped)")
        patches_applied += 1
    else:
        flag_pattern = (
            rb'(const [\w$]+="2358734848",)'
            rb"([\w$]+=\(\)=>)"
            rb"([\w$]+\([\w$]+\))"
        )

        def flag_replacement(m):
            return m.group(1) + m.group(2) + b'process.platform==="linux"||' + m.group(3)

        content, count = re.subn(flag_pattern, flag_replacement, content, count=1)
        if count >= 1:
            print(f"  [OK] Buddy flag: forced ON for Linux ({count} match)")
            patches_applied += 1
        else:
            print("  [FAIL] Buddy flag pattern not found")
            return False

    # ── Patch B: Early IPC stubs to prevent race condition ────────────
    #
    # The buddy_window renderer calls reportState("ready") during preload,
    # before the async BLE bridge init (setImplementation) completes.
    # Register no-op handlers early; they're replaced when the real bridge
    # calls setImplementation() (which does removeHandler then handle).

    already_b = b'_bi=require("electron").ipcMain' in content
    if already_b:
        print("  [OK] Early stubs: already patched (skipped)")
        patches_applied += 1
    else:
        uuid = extract_eipc_uuid(content)
        if not uuid:
            print("  [FAIL] Could not extract eipc UUID")
            return False

        eipc_prefix = f"$eipc_message$_{uuid}_$_"
        print(f"  [OK] Extracted eipc UUID: {uuid}")

        stub_js = build_early_stubs_js(eipc_prefix)

        pattern = rb'(app\.on\("ready",async\(\)=>\{)'
        replacement = rb"\1" + stub_js.encode("utf-8")

        content, count = re.subn(pattern, replacement, content, count=1)
        if count >= 1:
            print(f"  [OK] Early stubs: injected at app.on('ready') ({count} match)")
            patches_applied += 1
        else:
            print('  [FAIL] app.on("ready") pattern: 0 matches')
            return False

    if patches_applied < EXPECTED_PATCHES:
        print(f"  [FAIL] Only {patches_applied}/{EXPECTED_PATCHES} patches applied")
        return False

    if content != original_content:
        with open(filepath, "wb") as f:
            f.write(content)
        print("  [PASS] Buddy BLE enabled on Linux (flag + early stubs)")
        return True
    else:
        print("  [OK] Already patched, no changes needed")
        return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_buddy_ble(sys.argv[1])
    sys.exit(0 if success else 1)
