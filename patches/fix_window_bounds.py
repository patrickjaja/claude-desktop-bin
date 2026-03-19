#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Fix BrowserWindow child view bounds, ready-to-show jiggle, and Quick Entry blur.

Three related fixes for the Linux desktop experience:

1. Child view bounds: After maximize/unmaximize/KWin corner-snap, the child
   BrowserView (WebContentsView) doesn't resize to fill the window content area,
   leaving a blank white region. This happens because Chromium's LayoutManagerBase
   cache is only invalidated via _NET_WM_STATE atom changes, which KWin
   corner-snap/quick-tile never sets. We hook discrete state-change events and
   manually set child view bounds to match the content area.

2. Ready-to-show size jiggle: On first load, Chromium sometimes doesn't
   recalculate layout correctly. A brief +1px resize followed by restoration
   after 50ms forces a layout recalculation.

3. Quick Entry blur: When the Quick Entry window submits, it calls hide()
   directly. On Linux, this can leave focus in a bad state. Adding blur()
   before hide() ensures proper focus transfer to the previous window.

Reference: claude-desktop-debian/scripts/frame-fix-wrapper.js lines 134-194

Usage: python3 fix_window_bounds.py <path_to_index.js>
"""

import sys
import os
import re


# JavaScript block injected into the main window factory function.
# Uses an IIFE to avoid polluting the scope. All internal variables
# are prefixed with __wb_ to avoid collisions with minified code.
#
# The {win_var} placeholder is replaced at patch time with the actual
# minified variable name for the main window.
BOUNDS_FIX_JS = (
    b'(function(__wb_w){'
    b'if(process.platform!=="linux")return;'
    # fixChildBounds: set first child view bounds to match content size
    b'var __wb_fcb=function(){'
    b'if(__wb_w.isDestroyed())return;'
    b'var __wb_cv=__wb_w.contentView;'
    b'if(!__wb_cv||!__wb_cv.children||!__wb_cv.children.length)return;'
    b'var __wb_cs=__wb_w.getContentSize(),__wb_cw=__wb_cs[0],__wb_ch=__wb_cs[1];'
    b'if(__wb_cw<=0||__wb_ch<=0)return;'
    b'var __wb_cb=__wb_cv.children[0].getBounds();'
    b'if(__wb_cb.width!==__wb_cw||__wb_cb.height!==__wb_ch)'
    b'__wb_cv.children[0].setBounds({x:0,y:0,width:__wb_cw,height:__wb_ch})'
    b'};'
    # fixAfterStateChange: three-pass fix at 0/16/150ms
    b'var __wb_fasc=function(){__wb_fcb();setTimeout(__wb_fcb,16);setTimeout(__wb_fcb,150)};'
    # Hook discrete state-change events
    b'["maximize","unmaximize","enter-full-screen","leave-full-screen"]'
    b'.forEach(function(__wb_ev){__wb_w.on(__wb_ev,__wb_fasc)});'
    # Hook moved event with size-change guard (for KWin corner-snap)
    b'var __wb_lsz=[0,0];'
    b'__wb_w.on("moved",function(){'
    b'if(__wb_w.isDestroyed())return;'
    b'var __wb_s=__wb_w.getSize();'
    b'if(__wb_s[0]!==__wb_lsz[0]||__wb_s[1]!==__wb_lsz[1])'
    b'{__wb_lsz=__wb_s;__wb_fasc()}'
    b'});'
    # Ready-to-show size jiggle: +1px then restore after 50ms
    b'__wb_w.once("ready-to-show",function(){'
    b'var __wb_s=__wb_w.getSize();'
    b'__wb_w.setSize(__wb_s[0]+1,__wb_s[1]+1);'
    b'setTimeout(function(){'
    b'if(__wb_w.isDestroyed())return;'
    b'__wb_w.setSize(__wb_s[0],__wb_s[1]);'
    b'__wb_fasc()'
    b'},50)'
    b'})'
    b'})'
)


def patch_window_bounds(filepath):
    """Apply window bounds, size jiggle, and Quick Entry blur patches."""

    print(f"=== Patch: fix_window_bounds ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content
    applied = []

    # --- 1. Child view bounds fix + ready-to-show jiggle ---
    # Injected into the main window factory function (RIe in current version).
    # Pattern: function FUNC(PARAM){return WIN=new ELECTRON.BrowserWindow(PARAM),SETUP(WIN.webContents,ENUM.MAIN_WINDOW),WIN}
    # We inject an IIFE call before the final return value.

    bounds_marker = b'__wb_fcb'
    if bounds_marker in content:
        print(f"  [INFO] Window bounds fix already injected")
        applied.append("bounds-fix(skip)")
    else:
        # Match the main window factory function with flexible variable names
        # Variables may contain $ (e.g., $e), so use [\w$]+
        main_win_pattern = (
            rb'(function [\w$]+\([\w$]+\)\{return )'
            rb'([\w$]+)=new ([\w$]+)\.BrowserWindow\(([\w$]+)\),'
            rb'([\w$]+\(\2\.webContents,[\w$]+\.MAIN_WINDOW\)),'
            rb'\2\}'
        )

        def main_win_replacement(m):
            prefix = m.group(1)       # function RIe(t){return
            win_var = m.group(2)       # ut
            electron_var = m.group(3)  # Se
            param_var = m.group(4)     # t
            setup_call = m.group(5)    # Tk(ut.webContents,k_.MAIN_WINDOW)
            # Build the IIFE call with the actual window variable
            iife = BOUNDS_FIX_JS + b'(' + win_var + b')'
            return (
                prefix + win_var + b'=new ' + electron_var +
                b'.BrowserWindow(' + param_var + b'),' +
                setup_call + b',' +
                iife + b',' +
                win_var + b'}'
            )

        content, count = re.subn(main_win_pattern, main_win_replacement, content)
        if count > 0:
            print(f"  [OK] Window bounds fix + size jiggle injected: {count} match(es)")
            applied.append(f"bounds-fix({count})")
        else:
            print(f"  [FAIL] Main window factory pattern not matched")
            # Debug: show what the area looks like
            bw_match = re.search(rb'function \w+\(\w+\)\{return \w+=new \w+\.BrowserWindow', content)
            if bw_match:
                start = max(0, bw_match.start())
                print(f"  [DEBUG] Nearby pattern: ...{content[start:start+200].decode('utf-8', errors='replace')}...")

    # --- 2. Quick Entry blur before hide ---
    # Pattern: function FUNC(){GUARD()||VAR.hide()}
    # Replace with: function FUNC(){GUARD()||(VAR.blur(),VAR.hide())}

    # Check specifically for the Quick Entry hide pattern with blur
    qe_blur_check = rb'[\w$]+\.blur\(\),[\w$]+\.hide\(\)'
    if re.search(qe_blur_check, content):
        print(f"  [INFO] Quick Entry blur already applied")
        applied.append("qe-blur(skip)")
    else:
        # Match: function iW(){fR()||si.hide()}
        # The function is a simple guard-or-hide pattern
        qe_hide_pattern = rb'(function [\w$]+\(\)\{)([\w$]+\(\))\|\|([\w$]+)(\.hide\(\))\}'

        def qe_hide_replacement(m):
            func_decl = m.group(1)   # function iW(){
            guard_call = m.group(2)  # fR()
            win_var = m.group(3)     # si
            hide_call = m.group(4)   # .hide()
            return (
                func_decl + guard_call + b'||(' +
                win_var + b'.blur(),' +
                win_var + hide_call + b')}'
            )

        content, count = re.subn(qe_hide_pattern, qe_hide_replacement, content)
        if count > 0:
            print(f"  [OK] Quick Entry blur before hide: {count} match(es)")
            applied.append(f"qe-blur({count})")
        else:
            print(f"  [WARN] Quick Entry hide pattern not matched (non-critical)")

    # --- Summary ---
    if not applied:
        print(f"  [FAIL] No patches could be applied")
        return False

    if content != original_content:
        with open(filepath, 'wb') as f:
            f.write(content)
        print(f"  [PASS] Applied: {', '.join(applied)}")
        return True
    else:
        print(f"  [PASS] No changes needed (already patched)")
        return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_window_bounds(sys.argv[1])
    sys.exit(0 if success else 1)
