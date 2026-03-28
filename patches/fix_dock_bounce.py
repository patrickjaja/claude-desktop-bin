#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Suppress taskbar flashing (demands-attention) on Linux/Wayland+X11.

On KDE Plasma 6 (and other Linux DEs), Claude Desktop causes the taskbar
entry to flash orange and auto-hidden panels to pop up. This happens because
Electron's BrowserWindow.show(), BrowserWindow.focus(), and WebContents.focus()
internally trigger gtk_window_present() / XSetInputFocus() /
xdg_activation_v1, which set _NET_WM_STATE_DEMANDS_ATTENTION when the
compositor's focus-stealing prevention blocks the request.

This patch uses a two-layer approach:
Layer 1 (prevent): Monkey-patch Electron APIs to stop JS-level activation
  - flashFrame(true), app.focus(), BrowserWindow.focus(), BrowserWindow.show(),
    BrowserWindow.moveTop(), AND WebContents.focus() (the key missing piece
    that bypasses BrowserWindow.prototype overrides)
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
# - flashFrame(true) -> intercepted, only allow flashFrame(false) through
# - app.focus() -> no-op
# - BrowserWindow.focus() -> only when already focused
# - BrowserWindow.show() -> use showInactive() when app not focused
# - BrowserWindow.moveTop() -> block when not focused
# - WebContents.focus() -> block when parent window not focused (KEY FIX:
#   webContents.focus() bypasses BrowserWindow.prototype and directly calls
#   RenderWidgetHostViewAura::Focus() which triggers gtk_window_present()
#   or XSetInputFocus(), causing _NET_WM_STATE_DEMANDS_ATTENTION on KDE)
#
# Layer 2: Active clearing of demands-attention state
# - On every window blur, repeatedly call the REAL flashFrame(false)
#   to clear any demands-attention state set by Chromium internals
# - 500ms interval to catch delayed activation from compositor frame submission
LINUX_WAYLAND_GUARD = b""";(function(){
if(process.platform!=="linux")return;
var _e=require("electron");

/* 1. flashFrame: only allow flashFrame(false) to clear attention */
var _origFlash=_e.BrowserWindow.prototype.flashFrame;
_e.BrowserWindow.prototype.flashFrame=function(f){
if(!f&&!this.isDestroyed())return _origFlash.call(this,false);
};

/* 2. app.focus: complete no-op (prevents app-level activation request) */
_e.app.focus=function(){};

/* 3. BrowserWindow.focus: only call through if window already focused */
var _bwFocus=_e.BrowserWindow.prototype.focus;
_e.BrowserWindow.prototype.focus=function(){
if(!this.isDestroyed()&&this.isFocused())return _bwFocus.call(this);
};

/* 4. BrowserWindow.show: use showInactive when app not focused.
   showInactive() maps the window without calling gtk_window_present(),
   so KDE will not set _NET_WM_STATE_DEMANDS_ATTENTION */
var _bwShow=_e.BrowserWindow.prototype.show;
var _bwShowInactive=_e.BrowserWindow.prototype.showInactive;
_e.BrowserWindow.prototype.show=function(){
if(this.isDestroyed())return;
if(!this.isVisible()){
var _appFocused=_e.BrowserWindow.getAllWindows().some(function(w){
return!w.isDestroyed()&&w.isFocused();
});
if(_appFocused)return _bwShow.call(this);
return _bwShowInactive.call(this);
}
};

/* 5. BrowserWindow.moveTop: block when not focused */
var _bwMoveTop=_e.BrowserWindow.prototype.moveTop;
if(_bwMoveTop){
_e.BrowserWindow.prototype.moveTop=function(){
if(!this.isDestroyed()&&this.isFocused())return _bwMoveTop.call(this);
};
}

/* 6. WebContents.focus: block when parent window not focused.
   This is the KEY fix -- webContents.focus() internally calls
   RenderWidgetHostViewAura::Focus() which can trigger gtk_window_present()
   or XSetInputFocus(), causing _NET_WM_STATE_DEMANDS_ATTENTION on KDE */
_e.app.on("web-contents-created",function(_ev,wc){
var _wcFocus=wc.focus.bind(wc);
wc.focus=function(){
if(wc.isDestroyed())return;
var w=_e.BrowserWindow.fromWebContents(wc);
if(w&&!w.isDestroyed()&&w.isFocused())return _wcFocus();
if(!w){
var wins=_e.BrowserWindow.getAllWindows();
for(var i=0;i<wins.length;i++){
if(!wins[i].isDestroyed()&&wins[i].isFocused())return _wcFocus();
}
}
};
});

/* 7. Periodic flash-frame clearing when any window is blurred */
_e.app.whenReady().then(function(){
var _t=null;
function _clear(){
_e.BrowserWindow.getAllWindows().forEach(function(w){
if(!w.isDestroyed())try{_origFlash.call(w,false)}catch(_){}
});
}
_e.app.on("browser-window-blur",function(){
_clear();
if(_t)clearInterval(_t);
_t=setInterval(_clear,500);
});
_e.app.on("browser-window-focus",function(){
if(_t){clearInterval(_t);_t=null;}
});
});
})();"""


def patch_dock_bounce(filepath):
    """Suppress taskbar demands-attention on Linux."""

    print("=== Patch: fix_dock_bounce ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, "rb") as f:
        content = f.read()

    original_content = content
    applied = []

    # --- 1. Inject early monkey-patch block ---
    marker = b'_e.app.on("browser-window-blur"'
    if marker in content:
        print("  [INFO] Early monkey-patch already injected")
        applied.append("early-guard(skip)")
    else:
        # Remove any old version of the guard if present
        old_markers = [
            b"_e.app.focus=function(){}",
            b"_e.BrowserWindow.prototype.flashFrame=function(){}",
        ]
        for old_m in old_markers:
            if old_m in content and marker not in content:
                old_guard_pattern = rb';?\(function\(\)\{\s*if\(process\.platform==="linux"\)\{.*?\}\s*\}\)\(\);'
                content = re.sub(old_guard_pattern, b"", content, count=1, flags=re.DOTALL)
                print("  [OK] Removed old monkey-patch block")
                break

        # Inject right after "use strict"; at the top of the file
        if content.startswith(b'"use strict";'):
            content = b'"use strict";' + LINUX_WAYLAND_GUARD + content[len(b'"use strict";') :]
            print('  [OK] Early monkey-patch injected after "use strict"')
            applied.append("early-guard")
        else:
            content = LINUX_WAYLAND_GUARD + content
            print("  [OK] Early monkey-patch prepended")
            applied.append("early-guard(prepend)")

    # --- 2. Inline: strip steal from app.focus({steal:!0}) ---
    steal_pattern = rb"(\w+\.app\.focus)\(\{steal:!?[01t]\w*\}\)"

    def steal_replacement(m):
        return m.group(1) + b"({})"

    content, steal_count = re.subn(steal_pattern, steal_replacement, content)
    if steal_count > 0:
        print(f"  [OK] Removed app.focus({{steal}}) calls: {steal_count} match(es)")
        applied.append(f"steal-focus({steal_count})")
    else:
        print("  [INFO] No app.focus({steal}) calls found (may already be cleaned)")

    # --- 3. No-op requestUserAttention on Linux ---
    rua_pattern = rb"(requestUserAttention\(\)\{)(var \w+;this\.isAppFocusedAndVisible\(\)\|\|)"
    rua_replacement = rb'\1if(process.platform==="linux")return;\2'

    if b'requestUserAttention(){if(process.platform==="linux")return;' in content:
        print("  [INFO] requestUserAttention already guarded")
        applied.append("rua-guard(skip)")
    else:
        content, rua_count = re.subn(rua_pattern, rua_replacement, content)
        if rua_count > 0:
            print(f"  [OK] requestUserAttention Linux guard: {rua_count} match(es)")
            applied.append(f"rua-guard({rua_count})")
        else:
            print("  [WARN] requestUserAttention pattern not matched (non-critical)")

    # --- 4. Enable backgroundThrottling on Linux for mainView ---
    bg_pattern = rb"(enableBlinkFeatures:void 0,backgroundThrottling):(!1)"
    bg_replacement = rb'\1:process.platform!=="linux"?!1:!0'

    if b'backgroundThrottling:process.platform!=="linux"' in content:
        print("  [INFO] backgroundThrottling already patched")
        applied.append("bg-throttle(skip)")
    else:
        content, bg_count = re.subn(bg_pattern, bg_replacement, content)
        if bg_count > 0:
            print(f"  [OK] backgroundThrottling enabled on Linux: {bg_count} match(es)")
            applied.append(f"bg-throttle({bg_count})")
        else:
            print("  [WARN] backgroundThrottling pattern not matched (non-critical)")

    # --- Summary ---
    if not applied:
        print("  [FAIL] No patches could be applied")
        return False

    if content != original_content:
        with open(filepath, "wb") as f:
            f.write(content)
        print(f"  [PASS] Applied: {', '.join(applied)}")
        return True
    else:
        print("  [PASS] No changes needed (already patched)")
        return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_dock_bounce(sys.argv[1])
    sys.exit(0 if success else 1)
