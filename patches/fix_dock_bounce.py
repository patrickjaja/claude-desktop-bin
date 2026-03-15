#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Suppress taskbar flashing (demands-attention) on Linux/Wayland.

On KDE Plasma 6 (and other Wayland compositors), Claude Desktop causes the
taskbar entry to flash orange on every focus change. Monkey-patching Electron
JS APIs alone is NOT enough — the activation requests come from Chromium's
internal Wayland backend (xdg_activation_v1 surface activation during
compositor frame submission).

This patch uses a two-layer approach:
Layer 1 (prevent): Monkey-patch Electron APIs to stop JS-level activation
Layer 2 (cure):    Actively CLEAR demands-attention state on every blur event
                   using the real flashFrame(false), with retries to catch
                   delayed Chromium-internal activations

See: https://github.com/patrickjaja/claude-desktop-bin/issues/10

Usage: python3 fix_dock_bounce.py <path_to_index.js>
"""

import sys
import os
import re


# Early monkey-patch block injected at the top of index.js.
#
# Layer 1: Prevent JS-level activation requests
# - flashFrame(true) → intercepted, only allow flashFrame(false) through
# - app.focus() → no-op
# - BrowserWindow.focus() → only when already focused
# - BrowserWindow.show() → skip when already visible
#
# Layer 2: Active clearing of demands-attention state
# - On every window blur, repeatedly call the REAL flashFrame(false)
#   to clear any demands-attention state set by Chromium internals
# - Multiple retries (50ms, 100ms, 250ms, 500ms, 1s) to catch delayed
#   activation from compositor frame submission
LINUX_WAYLAND_GUARD = rb""";(function(){
if(process.platform==="linux"){
var _e=require("electron");
var _origFlash=_e.BrowserWindow.prototype.flashFrame;
_e.BrowserWindow.prototype.flashFrame=function(f){if(!f&&!this.isDestroyed())return _origFlash.call(this,false)};
_e.app.focus=function(){};
var _bwFocus=_e.BrowserWindow.prototype.focus;
_e.BrowserWindow.prototype.focus=function(){if(!this.isDestroyed()&&this.isFocused())return _bwFocus.call(this)};
var _bwShow=_e.BrowserWindow.prototype.show;
_e.BrowserWindow.prototype.show=function(){if(!this.isDestroyed()&&!this.isVisible())return _bwShow.call(this)};
_e.app.whenReady().then(function(){
var _t=null;
function _clear(){_e.BrowserWindow.getAllWindows().forEach(function(w){if(!w.isDestroyed())_origFlash.call(w,false)})}
_e.app.on("browser-window-blur",function(){_clear();if(_t)clearInterval(_t);_t=setInterval(_clear,200)});
_e.app.on("browser-window-focus",function(){if(_t){clearInterval(_t);_t=null}});
});
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
    marker = b'_e.app.on("browser-window-blur"'
    if marker in content:
        print(f"  [INFO] Early monkey-patch already injected")
        applied.append("early-guard(skip)")
    else:
        # Remove any old version of the guard if present
        old_markers = [
            b'_e.app.focus=function(){}',
            b'_e.BrowserWindow.prototype.flashFrame=function(){}',
        ]
        for old_m in old_markers:
            if old_m in content and marker not in content:
                old_guard_pattern = rb';?\(function\(\)\{\s*if\(process\.platform==="linux"\)\{.*?\}\s*\}\)\(\);'
                content = re.sub(old_guard_pattern, b'', content, count=1, flags=re.DOTALL)
                print(f"  [OK] Removed old monkey-patch block")
                break

        # Inject right after "use strict"; at the top of the file
        if content.startswith(b'"use strict";'):
            content = b'"use strict";' + LINUX_WAYLAND_GUARD + content[len(b'"use strict";'):]
            print(f"  [OK] Early monkey-patch injected after \"use strict\"")
            applied.append("early-guard")
        else:
            content = LINUX_WAYLAND_GUARD + content
            print(f"  [OK] Early monkey-patch prepended")
            applied.append("early-guard(prepend)")

    # --- 2. Inline: strip steal from app.focus({steal:!0}) ---
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
