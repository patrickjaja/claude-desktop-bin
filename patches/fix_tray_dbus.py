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

    print(f"Patching tray DBus handler in: {filepath}")

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content
    patches_applied = 0

    # Step 1: Find the tray function name from menuBarEnabled listener
    # Pattern: on("menuBarEnabled",()=>{FUNCNAME()})
    match = re.search(rb'on\("menuBarEnabled",\(\)=>\{(\w+)\(\)\}\)', content)
    if not match:
        print("  Warning: Could not find menuBarEnabled listener")
        return False

    tray_func = match.group(1)
    print(f"  Found tray function: {tray_func.decode()}")

    # Step 2: Find tray variable name
    # Pattern: });let TRAYVAR=null;function FUNCNAME or });let TRAYVAR=null;async function FUNCNAME
    pattern = rb'\}\);let (\w+)=null;(?:async )?function ' + tray_func
    match = re.search(pattern, content)
    if not match:
        print("  Warning: Could not find tray variable")
        return False

    tray_var = match.group(1)
    print(f"  Found tray variable: {tray_var.decode()}")

    # Step 3: Make the function async (if not already)
    old_func = b'function ' + tray_func + b'(){'
    new_func = b'async function ' + tray_func + b'(){'
    if old_func in content and b'async function ' + tray_func not in content:
        content = content.replace(old_func, new_func)
        patches_applied += 1
        print(f"  Made {tray_func.decode()}() async")

    # Step 4: Find first const variable in the function
    # Pattern: async function FUNCNAME(){const VARNAME= or with mutex already
    pattern = rb'async function ' + tray_func + rb'\(\)\{(?:if\(' + tray_func + rb'\._running\)[^}]*?)?const (\w+)='
    match = re.search(pattern, content)
    if not match:
        print("  Warning: Could not find first const in function")
        return False

    first_const = match.group(1)
    print(f"  Found first const: {first_const.decode()}")

    # Step 5: Add mutex guard (if not already present)
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
            patches_applied += 1
            print(f"  Added mutex guard to {tray_func.decode()}()")
    else:
        print(f"  Mutex guard already present")

    # Step 6: Add delay after Tray.destroy() for DBus cleanup
    # Pattern: TRAYVAR&&(TRAYVAR.destroy(),TRAYVAR=null)
    old_destroy = tray_var + b'&&(' + tray_var + b'.destroy(),' + tray_var + b'=null)'
    new_destroy = tray_var + b'&&(' + tray_var + b'.destroy(),' + tray_var + b'=null,await new Promise(r=>setTimeout(r,50)))'

    if old_destroy in content and b'await new Promise' not in content:
        content = content.replace(old_destroy, new_destroy)
        patches_applied += 1
        print(f"  Added DBus cleanup delay after {tray_var.decode()}.destroy()")
    elif b'await new Promise' in content:
        print(f"  DBus cleanup delay already present")

    if content != original_content:
        with open(filepath, 'wb') as f:
            f.write(content)
        print(f"Tray DBus patches applied: {patches_applied}")
        return True
    else:
        print("Warning: No tray DBus patches applied")
        return False


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    filepath = sys.argv[1]
    if not os.path.exists(filepath):
        print(f"Error: File not found: {filepath}")
        sys.exit(1)

    patch_tray_dbus(filepath)
    # Always exit 0 - patch is best-effort
    sys.exit(0)
