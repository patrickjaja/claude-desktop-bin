#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Patch Claude Desktop Quick Entry to spawn on the monitor where the cursor is,
and to auto-focus the input field on Linux.

Patches:
1. Replace getPrimaryDisplay() with getDisplayNearestPoint() using real cursor
   position. On Linux, Electron's getCursorScreenPoint() returns STALE coordinates
   (only updates when cursor passes over an Electron window), so we use xdotool
   to query X11 for the actual cursor position, with getCursorScreenPoint() as
   fallback for Wayland/macOS/Windows or if xdotool is unavailable.
2. (Optional) Fallback display lookup — same xdotool-based cursor fix.
3. Override position-save/restore to always use cursor's display.
4. On Linux: show() + setBounds() retries to counter WM smart-placement,
   plus webContents.focus() and executeJavaScript to focus #prompt-input
   (which only auto-focuses on initial page load, not on re-show).

Usage: python3 fix_quick_entry_position.py <path_to_index.js>
"""

import sys
import os
import re


def patch_quick_entry_position(filepath):
    """Patch Quick Entry to spawn on cursor's monitor instead of primary display."""

    print("=== Patch: fix_quick_entry_position ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, "rb") as f:
        content = f.read()

    original_content = content
    failed = False

    # Helper: generate an IIFE that gets the REAL cursor position on Linux.
    # Electron's getCursorScreenPoint() on Linux/X11 returns STALE coordinates —
    # it only updates when the cursor passes over an Electron-owned window.
    # Fallback chain: xdotool (X11/XWayland) → hyprctl (Hyprland) → Electron API.
    def _cursor_iife(electron_var):
        """Return JS IIFE string that resolves to {x, y} cursor position."""
        return (
            f"(()=>{{"
            f'if(process.platform==="linux"){{'
            f'const cp=require("child_process");'
            # Try xdotool first (works on X11 and XWayland)
            f"try{{"
            f'const r=cp.execFileSync("xdotool",["getmouselocation","--shell"],'
            f'{{timeout:200,encoding:"utf-8"}});'
            f"const x=parseInt(r.match(/X=(\\d+)/)?.[1]);"
            f"const y=parseInt(r.match(/Y=(\\d+)/)?.[1]);"
            f"if(!isNaN(x)&&!isNaN(y))return{{x,y}}"
            f"}}catch(e){{}}"
            # Try hyprctl for Hyprland on Wayland
            f"try{{"
            f'const r=cp.execFileSync("hyprctl",["cursorpos"],'
            f'{{timeout:200,encoding:"utf-8"}});'
            f"const m=r.match(/(\\d+),\\s*(\\d+)/);"
            f"if(m)return{{x:parseInt(m[1]),y:parseInt(m[2])}}"
            f"}}catch(e){{}}"
            f"}}"
            f"return {electron_var}.screen.getCursorScreenPoint()"
            f"}})()"
        )

    # Patch 1: In position function - the Quick Entry centering function
    # Pattern matches: function FUNCNAME(){const t=ELECTRON.screen.getPrimaryDisplay()
    # Function names change between versions (pTe, lPe, kFt, etc.)
    # Electron var may contain $ (e.g. $e), so use [\w$]+
    pattern1 = rb"(function [\w$]+\(\)\{const [\w$]+=)([\w$]+)(\.screen\.)getPrimaryDisplay\(\)"

    def replacement1_func(m):
        electron_var = m.group(2).decode("utf-8")
        cursor = _cursor_iife(electron_var)
        return m.group(1) + m.group(2) + m.group(3) + f"getDisplayNearestPoint({cursor})".encode("utf-8")

    content, count1 = re.subn(pattern1, replacement1_func, content)
    if count1 > 0:
        print(f"  [OK] position function: {count1} match(es)")
    else:
        print("  [FAIL] position function: 0 matches, expected >= 1")
        failed = True

    # Patch 2 (optional): Fallback display lookup
    # Pattern: VAR||(VAR=ELECTRON.screen.getPrimaryDisplay())
    # This lazy-init pattern was removed in newer versions, so it's optional.
    pattern2 = rb"([\w$])\|\|\(\1=([\w$]+)\.screen\.getPrimaryDisplay\(\)\)"

    def replacement2_func(m):
        var_name = m.group(1).decode("utf-8")
        electron_var = m.group(2).decode("utf-8")
        cursor = _cursor_iife(electron_var)
        return f"{var_name}||({var_name}={electron_var}.screen.getDisplayNearestPoint({cursor}))".encode("utf-8")

    content, count2 = re.subn(pattern2, replacement2_func, content)
    if count2 > 0:
        print(f"  [OK] fallback display: {count2} match(es)")
    else:
        print("  [INFO] fallback display: 0 matches (pattern removed in this version, optional)")

    # Patch 3: Override position-restore function to always use cursor's display
    # In v1.1.7714+, T7t() saves/restores Quick Entry position per-monitor,
    # bypassing our cursor-based I7t() patch. We make it always delegate to
    # the centering function (now cursor-aware via Patch 1) by short-circuiting
    # the saved position check.
    # Pattern: function T7t(){const t=Ki.get("quickWindowPosition",null),...if(!(t&&t.absolute...))return I7t();
    # We replace the saved-position guard to always return the centering function.
    pattern3 = rb'(function [\w$]+\(\)\{const [\w$]+=[\w$]+\.get\("quickWindowPosition",null\),[\w$]+=[\w$]+\.screen\.getAllDisplays\(\);if\(!\()[\w$]+&&[\w$]+\.absolutePointInWorkspace&&[\w$]+\.monitor&&[\w$]+\.relativePointFromMonitor(\)\)return )([\w$]+)\(\)'

    def replacement3_func(m):
        # Replace condition with !1 (false), so !(!1) = !(false) = true → always returns centering fn
        return m.group(1) + b"!1" + m.group(2) + m.group(3) + b"()"

    content, count3 = re.subn(pattern3, replacement3_func, content)
    if count3 > 0:
        print(f"  [OK] position restore override: {count3} match(es)")
    else:
        print("  [INFO] position restore override: 0 matches (older version without saved position)")

    # Patch 4: Fix show/positioning + focus on Linux — pure Electron APIs
    # On macOS, type:"panel" auto-focuses and the WM respects position hints.
    # On Linux/X11, show() triggers WM smart-placement which can override
    # our position. We counter this with setBounds() retries.
    # On Linux/Wayland, setPosition is not supported — setBounds is best-effort.
    #
    # The input field (#prompt-input) only auto-focuses on initial page load.
    # On re-show (hide/show cycle), we must explicitly focus it via
    # executeJavaScript since webContents.focus() only focuses the renderer
    # process, not the DOM input element.
    #
    # Strategy:
    # 1. Pre-position with setBounds() while hidden
    # 2. show() for proper window activation and focus
    # 3. Immediate setBounds() to counter WM placement
    # 4. setBounds() retries at 50/150ms as safety net
    # 5. webContents.focus() + executeJavaScript to focus #prompt-input
    #
    # Pattern: WIN.show()}return WIN.setPosition(Math.round(VAR.x),Math.round(VAR.y)),!0}
    # Window var changes between versions (ai, Js, etc.), so capture it dynamically.
    pattern4 = rb"([\w$]+)\.show\(\)\}return \1\.setPosition\(Math\.round\(([\w$]+)\.x\),Math\.round\(\2\.y\)\),!0\}"

    def replacement4_func(m):
        w = m.group(1).decode("utf-8")  # window variable (e.g., Js, ai)
        v = m.group(2).decode("utf-8")  # position variable (e.g., t)
        return (
            f"(()=>{{"
            f"const _b={{x:Math.round({v}.x),y:Math.round({v}.y),"
            f"width:{w}.getBounds().width,height:{w}.getBounds().height}};"
            f"const _r=()=>{{{w}.isDestroyed()||{w}.setBounds(_b)}};"
            # Pre-position, show, immediate re-position
            f"{w}.setBounds(_b);"
            f"{w}.show();"
            f"_r();"
            # Focus: window (OS-level) → webContents (renderer) → DOM input
            f"{w}.focus();"
            f"{w}.webContents.focus();"
            f"{w}.webContents.executeJavaScript("
            f"'document.getElementById(\"prompt-input\")?.focus()'"
            f").catch(()=>{{}});"
            # Safety retries — counter async WM placement + re-assert focus
            f"setTimeout(()=>{{if(!{w}.isDestroyed()){{"
            f"_r();{w}.focus();{w}.webContents.focus();"
            f"{w}.webContents.executeJavaScript("
            f"'document.getElementById(\"prompt-input\")?.focus()'"
            f").catch(()=>{{}})"
            f"}}}},50);"
            f"setTimeout(_r,150)"
            f"}})()}}"
            f"return!0}}"
        ).encode("utf-8")

    content, count4 = re.subn(pattern4, replacement4_func, content)
    if count4 > 0:
        print(f"  [OK] show/focus ordering fix: {count4} match(es)")
    else:
        print("  [FAIL] show/focus ordering: 0 matches")
        failed = True

    # Check results
    if failed:
        print("  [FAIL] Required patterns did not match")
        return False

    # Write back if changed
    if content != original_content:
        with open(filepath, "wb") as f:
            f.write(content)
        print("  [PASS] Quick Entry position patched successfully")
        return True
    else:
        print("  [WARN] No changes made (patterns may have already been applied)")
        return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_quick_entry_position(sys.argv[1])
    sys.exit(0 if success else 1)
