#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/renderer/main_window/assets/MainWindowPage-*.js
# @patch-type: python
"""
Fix title bar rendering on Linux in the React renderer.

The MainWindowPage component has a title bar function _e() that on non-Windows
platforms (when isMainWindow=true) renders only a plain drag div with no
hamburger menu button.

This patch replaces the platform-gated early return with a functional title bar
that includes:
- A hamburger menu button that triggers requestMainMenuPopup() via IPC
- A draggable title area showing "Claude"
- A bottom border matching the app's style

The IPC interface (MainWindowTitleBar.requestMainMenuPopup) is already wired up
in the main process and exposed via the mainWindow.js preload script.

Usage: python3 fix_title_bar_renderer.py <path_to_MainWindowPage.js>
"""

import sys
import os
import re


def patch_title_bar_renderer(filepath):
    """Add hamburger menu button to Linux title bar."""

    print(f"=== Patch: fix_title_bar_renderer ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content
    failed = False

    # Find the platform variable assignments:
    #   const K=H?0:36,we=H?28:36;
    # H is isMac (process.platform==="darwin"), imported from main module.
    # On Linux, H=false so K=36, we=36.
    # We don't need to change these.

    # Find the _e title bar function and its platform-gated early return:
    #   function _e({isMainWindow:e,windowTitle:t,titleBarHeight:r=e?K:we}){
    #     if(!W&&e)return r===0?null:o.jsx("div",{className:"nc-drag",style:{height:`${r}px`,width:"100%"}});
    #     if(e)return null;
    #
    # W is isWindows (process.platform==="win32"), imported from main module.
    # On Linux: !W&&e is true, so it returns a plain drag div.
    #
    # We replace the plain drag div return with a functional title bar that has
    # a hamburger menu button.

    # Pattern: match the !W&&e early return for main window
    # The pattern captures the full early return including the ternary
    pattern = (
        rb'(function \w+\(\{isMainWindow:\w+,windowTitle:(\w+),titleBarHeight:(\w+)=[^}]+\}\)\{)'
        rb'if\(!\w+&&\w+\)return \3===0\?null:'
        rb'(\w+)\.jsx\("div",\{className:"nc-drag",style:\{height:`\$\{\3\}px`,width:"100%"\}\}\);'
    )

    def replacement(m):
        func_start = m.group(1).decode('utf-8')
        t_var = m.group(2).decode('utf-8')  # windowTitle
        r_var = m.group(3).decode('utf-8')  # titleBarHeight
        o_var = m.group(4).decode('utf-8')  # jsx namespace (o)

        # Build a title bar with hamburger button that calls requestMainMenuPopup
        # s is globalThis["claude.internal.ui"]?.MainWindowTitleBar (already in scope)
        result = (
            f'{func_start}'
            f'if(!W&&e)return {r_var}===0?null:'
            f'{o_var}.jsxs("div",{{className:"flex flex-row items-center select-none",style:{{height:`${{{r_var}}}px`,width:"100%",borderBottom:"1px solid rgba(0,0,0,0.1)"}},children:['
            f'{o_var}.jsx("div",{{className:"flex items-center justify-center cursor-pointer",style:{{width:"36px",height:"36px",opacity:"0.6",fontSize:"18px"}},onClick:()=>{{var n;(n=s==null?void 0:s.requestMainMenuPopup)==null||n.call(s)}},children:"\u2630"}}),'
            f'{o_var}.jsx("div",{{className:"flex-1 text-center nc-drag",style:{{fontSize:"12px",opacity:"0.4",fontWeight:"700"}},children:{t_var}}})'
            f']}});'
        )
        return result.encode('utf-8')

    content, count = re.subn(pattern, replacement, content, count=1)
    if count == 1:
        print(f"  [OK] Title bar hamburger menu: 1 match")
    else:
        print(f"  [FAIL] Title bar function pattern: {count} matches, expected 1")
        failed = True

    if failed:
        print("  [FAIL] Required patterns did not match")
        return False

    if content != original_content:
        with open(filepath, 'wb') as f:
            f.write(content)
        print("  [PASS] Title bar with hamburger menu enabled for Linux")
        return True
    else:
        print("  [WARN] No changes made")
        return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_MainWindowPage.js>")
        sys.exit(1)

    success = patch_title_bar_renderer(sys.argv[1])
    sys.exit(0 if success else 1)
