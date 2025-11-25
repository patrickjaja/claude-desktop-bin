#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Patch Claude Desktop tray menu handler to prevent DBus race conditions.

The tray icon setup can be called multiple times concurrently, causing DBus
"already exported" errors. This patch:
1. Makes the tray function async
2. Adds a mutex guard to prevent concurrent calls
3. Adds a delay after Tray.destroy() to allow DBus cleanup

Based on: https://github.com/aaddrick/claude-desktop-debian/blob/main/build.sh

Usage: python3 fix_tray_dbus.py <path_to_index.js>
"""

import sys
import os
import re


def patch_tray_dbus(filepath):
    """Patch the tray menu handler to prevent DBus race conditions."""

    print(f"=== Patch: fix_tray_dbus ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content
    failed = False

    # Step 1: Find the tray function name from menuBarEnabled listener
    match = re.search(rb'on\("menuBarEnabled",\(\)=>\{(\w+)\(\)\}\)', content)
    if not match:
        print("  [FAIL] menuBarEnabled listener: 0 matches, expected >= 1")
        failed = True
        tray_func = None
    else:
        tray_func = match.group(1)
        print(f"  [OK] menuBarEnabled listener: found tray function '{tray_func.decode()}'")

    # Step 2: Find tray variable name
    tray_var = None
    if tray_func:
        pattern = rb'\}\);let (\w+)=null;(?:async )?function ' + tray_func
        match = re.search(pattern, content)
        if not match:
            print("  [FAIL] tray variable: 0 matches, expected >= 1")
            failed = True
        else:
            tray_var = match.group(1)
            print(f"  [OK] tray variable: found '{tray_var.decode()}'")

    # Step 3: Make the function async (if not already)
    if tray_func:
        old_func = b'function ' + tray_func + b'(){'
        new_func = b'async function ' + tray_func + b'(){'
        if old_func in content and b'async function ' + tray_func not in content:
            content = content.replace(old_func, new_func)
            print(f"  [OK] async conversion: made {tray_func.decode()}() async")
        elif b'async function ' + tray_func in content:
            print(f"  [INFO] async conversion: already async")
        else:
            print(f"  [FAIL] async conversion: function pattern not found")
            failed = True

    # Step 4: Find first const variable in the function
    first_const = None
    if tray_func:
        pattern = rb'async function ' + tray_func + rb'\(\)\{(?:if\(' + tray_func + rb'\._running\)[^}]*?)?const (\w+)='
        match = re.search(pattern, content)
        if not match:
            print("  [FAIL] first const in function: 0 matches")
            failed = True
        else:
            first_const = match.group(1)
            print(f"  [OK] first const in function: found '{first_const.decode()}'")

    # Step 5: Add mutex guard (if not already present)
    if tray_func and first_const:
        mutex_check = tray_func + b'._running'
        if mutex_check not in content:
            old_start = b'async function ' + tray_func + b'(){const ' + first_const + b'='
            mutex_code = (
                b'async function ' + tray_func + b'(){if(' + tray_func + b'._running)return;' +
                tray_func + b'._running=true;setTimeout(()=>' + tray_func + b'._running=false,500);const ' +
                first_const + b'='
            )
            if old_start in content:
                content = content.replace(old_start, mutex_code)
                print(f"  [OK] mutex guard: added")
            else:
                print(f"  [FAIL] mutex guard: insertion point not found")
                failed = True
        else:
            print(f"  [INFO] mutex guard: already present")

    # Step 6: Add delay after Tray.destroy() for DBus cleanup
    if tray_var:
        old_destroy = tray_var + b'&&(' + tray_var + b'.destroy(),' + tray_var + b'=null)'
        new_destroy = tray_var + b'&&(' + tray_var + b'.destroy(),' + tray_var + b'=null,await new Promise(r=>setTimeout(r,50)))'

        if old_destroy in content and b'await new Promise' not in content:
            content = content.replace(old_destroy, new_destroy)
            print(f"  [OK] DBus cleanup delay: added after {tray_var.decode()}.destroy()")
        elif b'await new Promise' in content:
            print(f"  [INFO] DBus cleanup delay: already present")
        else:
            print(f"  [FAIL] DBus cleanup delay: destroy pattern not found")
            failed = True

    # Check results
    if failed:
        print("  [FAIL] Some required patterns did not match")
        return False

    # Write back if changed
    if content != original_content:
        with open(filepath, 'wb') as f:
            f.write(content)
        print("  [PASS] All required patterns matched and applied")
        return True
    else:
        print("  [WARN] No changes made (patterns may have already been applied)")
        return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_tray_dbus(sys.argv[1])
    sys.exit(0 if success else 1)
