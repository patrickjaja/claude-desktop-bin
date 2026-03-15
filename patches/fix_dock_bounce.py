#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Suppress taskbar flashing (demands-attention) on Linux/Wayland.

On KDE Plasma 6 (and other Wayland compositors), Claude Desktop causes the
taskbar entry to flash orange on every focus change. This is NOT caused by
flashFrame() (dockBounceEnabled defaults to false). The real causes are:

1. app.focus({steal:true}) — Electron docs explicitly state this "requests
   focus, which may result in a flashing app icon" on Wayland
2. BrowserWindow.focus()/show() on non-focused windows — generates
   xdg_activation_v1 requests that KWin translates to demands-attention

This patch injects early monkey-patches that:
- No-op flashFrame() on Linux (belt-and-suspenders)
- Strip {steal:true} from app.focus() to prevent Wayland activation requests
- Guard BrowserWindow.focus() to skip when the app doesn't own focus
- No-op requestUserAttention() on Linux entirely

See: https://github.com/patrickjaja/claude-desktop-bin/issues/10

Usage: python3 fix_dock_bounce.py <path_to_index.js>
"""

import sys
import os
import re


# Early monkey-patch block injected at the top of index.js.
# This runs before any BrowserWindow is created, ensuring all
# subsequent calls go through our guards.
LINUX_WAYLAND_GUARD = rb""";(function(){
if(process.platform==="linux"){
var _e=require("electron");
_e.BrowserWindow.prototype.flashFrame=function(){};
var _appFocus=_e.app.focus.bind(_e.app);
_e.app.focus=function(o){if(o)delete o.steal;return _appFocus(o)};
var _bwFocus=_e.BrowserWindow.prototype.focus;
_e.BrowserWindow.prototype.focus=function(){if(this.isDestroyed())return;try{if(!this.isFocused()&&!this.isVisible())return}catch(e){}return _bwFocus.call(this)};
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
    marker = b'_e.BrowserWindow.prototype.flashFrame=function(){}'
    if marker in content:
        print(f"  [INFO] Early monkey-patch already injected")
        applied.append("early-guard(skip)")
    else:
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
    # Pattern: xe.app.focus({steal:!0})  or  xe.app.focus({steal:true})
    # Replace with: xe.app.focus({})
    steal_pattern = rb'(\w+\.app\.focus)\(\{steal:!?[01t]\w*\}\)'

    def steal_replacement(m):
        return m.group(1) + b'({})'

    content, steal_count = re.subn(steal_pattern, steal_replacement, content)
    if steal_count > 0:
        print(f"  [OK] Removed app.focus({{steal}}) calls: {steal_count} match(es)")
        applied.append(f"steal-focus({steal_count})")
    else:
        print(f"  [INFO] No app.focus({{steal}}) calls found (may not exist in this version)")

    # --- 3. No-op requestUserAttention on Linux ---
    # Pattern: requestUserAttention(){...flashFrame...}
    # We wrap the body with a platform guard
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
