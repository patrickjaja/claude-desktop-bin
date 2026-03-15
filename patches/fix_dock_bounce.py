#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Suppress taskbar flashing (demands-attention) on Linux/Wayland.

On KDE Plasma 6 (and other Wayland compositors), Claude Desktop causes the
taskbar entry to flash orange on every focus change. The root causes are:

1. app.focus({steal:true}) — Electron docs: "may result in a flashing app
   icon" on Wayland
2. BrowserWindow.focus()/show() on non-focused windows — generates
   xdg_activation_v1 requests that KWin translates to demands-attention
3. backgroundThrottling:false on the BrowserView — the renderer keeps
   compositing frames in the background, generating activation requests

This patch:
- No-ops flashFrame(), app.focus() on Linux entirely
- Guards BrowserWindow.focus() to only work when already focused (WM handles
  activation on Linux — clicking taskbar icon works through WM, not JS)
- Guards BrowserWindow.show() to skip when window is already visible
- Enables backgroundThrottling on Linux to stop background compositor activity
- No-ops requestUserAttention() on Linux

See: https://github.com/patrickjaja/claude-desktop-bin/issues/10

Usage: python3 fix_dock_bounce.py <path_to_index.js>
"""

import sys
import os
import re


# Early monkey-patch block injected at the top of index.js.
# This runs before any BrowserWindow is created, ensuring all
# subsequent calls go through our guards.
#
# On Linux (especially Wayland), we suppress ALL focus-stealing and
# activation-requesting behavior. The window manager owns focus management;
# the app should never try to grab focus or request attention.
LINUX_WAYLAND_GUARD = rb""";(function(){
if(process.platform==="linux"){
var _e=require("electron");
_e.BrowserWindow.prototype.flashFrame=function(){};
_e.app.focus=function(){};
var _bwFocus=_e.BrowserWindow.prototype.focus;
_e.BrowserWindow.prototype.focus=function(){if(!this.isDestroyed()&&this.isFocused())return _bwFocus.call(this)};
var _bwShow=_e.BrowserWindow.prototype.show;
_e.BrowserWindow.prototype.show=function(){if(!this.isDestroyed()&&!this.isVisible())return _bwShow.call(this)};
}
})();"""


def patch_dock_bounce(filepath):
    """Suppress taskbar demands-attention on Linux."""

    print(f"=== Patch: fix_dock_bounce ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content
    applied = []

    # --- 1. Inject early monkey-patch block ---
    marker = b'_e.app.focus=function(){}'
    if marker in content:
        print(f"  [INFO] Early monkey-patch already injected")
        applied.append("early-guard(skip)")
    else:
        # Remove old version of the guard if present (from previous patch)
        old_marker = b'_e.BrowserWindow.prototype.flashFrame=function(){}'
        if old_marker in content and marker not in content:
            # Strip old guard block and inject new one
            old_guard_pattern = rb';?\(function\(\)\{\s*if\(process\.platform==="linux"\)\{.*?\}\s*\}\)\(\);'
            content = re.sub(old_guard_pattern, b'', content, count=1, flags=re.DOTALL)
            print(f"  [OK] Removed old monkey-patch block")

        # Inject right after "use strict"; at the top of the file
        if content.startswith(b'"use strict";'):
            content = b'"use strict";' + LINUX_WAYLAND_GUARD + content[len(b'"use strict";'):]
            print(f"  [OK] Early monkey-patch injected after \"use strict\"")
            applied.append("early-guard")
        else:
            # Fallback: prepend
            content = LINUX_WAYLAND_GUARD + content
            print(f"  [OK] Early monkey-patch prepended")
            applied.append("early-guard(prepend)")

    # --- 2. Inline: strip steal from app.focus({steal:!0}) ---
    # Even though app.focus is now a no-op, remove steal inline too
    # for clarity and in case someone reads the code
    steal_pattern = rb'(\w+\.app\.focus)\(\{steal:!?[01t]\w*\}\)'

    def steal_replacement(m):
        return m.group(1) + b'({})'

    content, steal_count = re.subn(steal_pattern, steal_replacement, content)
    if steal_count > 0:
        print(f"  [OK] Removed app.focus({{steal}}) calls: {steal_count} match(es)")
        applied.append(f"steal-focus({steal_count})")
    else:
        print(f"  [INFO] No app.focus({{steal}}) calls found (may already be cleaned)")

    # --- 3. No-op requestUserAttention on Linux ---
    rua_pattern = rb'(requestUserAttention\(\)\{)(var \w+;this\.isAppFocusedAndVisible\(\)\|\|)'
    rua_replacement = rb'\1if(process.platform==="linux")return;\2'

    if b'requestUserAttention(){if(process.platform==="linux")return;' in content:
        print(f"  [INFO] requestUserAttention already guarded")
        applied.append("rua-guard(skip)")
    else:
        content, rua_count = re.subn(rua_pattern, rua_replacement, content)
        if rua_count > 0:
            print(f"  [OK] requestUserAttention Linux guard: {rua_count} match(es)")
            applied.append(f"rua-guard({rua_count})")
        else:
            print(f"  [WARN] requestUserAttention pattern not matched (non-critical)")

    # --- 4. Enable backgroundThrottling on Linux for mainView ---
    # Original: backgroundThrottling:!1 (false — renderer never throttles)
    # On Linux, this causes the renderer to keep compositing frames while
    # backgrounded, generating xdg_activation_v1 requests on Wayland.
    # Change to: backgroundThrottling:process.platform!=="linux"
    # (true on Linux = throttle when backgrounded, false on others = unchanged)
    bg_pattern = rb'(enableBlinkFeatures:void 0,backgroundThrottling):(!1)'
    bg_replacement = rb'\1:process.platform!=="linux"?!1:!0'

    if b'backgroundThrottling:process.platform!=="linux"' in content:
        print(f"  [INFO] backgroundThrottling already patched")
        applied.append("bg-throttle(skip)")
    else:
        content, bg_count = re.subn(bg_pattern, bg_replacement, content)
        if bg_count > 0:
            print(f"  [OK] backgroundThrottling enabled on Linux: {bg_count} match(es)")
            applied.append(f"bg-throttle({bg_count})")
        else:
            print(f"  [WARN] backgroundThrottling pattern not matched (non-critical)")

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

    success = patch_dock_bounce(sys.argv[1])
    sys.exit(0 if success else 1)
