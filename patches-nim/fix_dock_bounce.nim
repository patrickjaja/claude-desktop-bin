# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
# Nim port of fix_dock_bounce.py.

import std/[os, strformat, strutils]
import regex

const LinuxWaylandGuard = """;(function(){
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

proc apply*(input: string): string =
  var content = input
  var applied: seq[string] = @[]

  # --- 1. Inject early monkey-patch block ---
  const marker = "_e.app.on(\"browser-window-blur\""
  if marker in content:
    echo "  [INFO] Early monkey-patch already injected"
    applied.add "early-guard(skip)"
  else:
    # Old markers removal
    const oldMarkers = ["_e.app.focus=function(){}", "_e.BrowserWindow.prototype.flashFrame=function(){}"]
    for oldM in oldMarkers:
      if oldM in content and marker notin content:
        # re with DOTALL: python uses re.DOTALL. nim-regex needs (?s) inline flag.
        let oldGuardPattern = re2"""(?s);?\(function\(\)\{\s*if\(process\.platform==="linux"\)\{.*?\}\s*\}\)\(\);"""
        let counter = new int
        counter[] = 0
        content = content.replace(oldGuardPattern, proc (m: RegexMatch2, s: string): string =
          inc counter[]
          ""
        , limit = 1)
        if counter[] > 0:
          echo "  [OK] Removed old monkey-patch block"
        break

    if content.startsWith("\"use strict\";"):
      content = "\"use strict\";" & LinuxWaylandGuard & content["\"use strict\";".len .. ^1]
      echo "  [OK] Early monkey-patch injected after \"use strict\""
      applied.add "early-guard"
    else:
      content = LinuxWaylandGuard & content
      echo "  [OK] Early monkey-patch prepended"
      applied.add "early-guard(prepend)"

  # --- 2. Strip steal from app.focus({steal:!0}) ---
  let stealPattern = re2"""([\w$]+\.app\.focus)\(\{steal:!?[01t][\w$]*\}\)"""
  let stealCounter = new int
  stealCounter[] = 0
  content = content.replace(stealPattern, proc (m: RegexMatch2, s: string): string =
    inc stealCounter[]
    s[m.group(0)] & "({})"
  )
  if stealCounter[] > 0:
    echo &"  [OK] Removed app.focus({{steal}}) calls: {stealCounter[]} match(es)"
    applied.add &"steal-focus({stealCounter[]})"
  else:
    echo "  [INFO] No app.focus({steal}) calls found (may already be cleaned)"

  # --- 3. No-op requestUserAttention on Linux ---
  let ruaPattern = re2"""(requestUserAttention\(\)\{)(var [\w$]+;this\.isAppFocusedAndVisible\(\)\|\|)"""
  if """requestUserAttention(){if(process.platform==="linux")return;""" in content:
    echo "  [INFO] requestUserAttention already guarded"
    applied.add "rua-guard(skip)"
  else:
    let ruaCounter = new int
    ruaCounter[] = 0
    content = content.replace(ruaPattern, proc (m: RegexMatch2, s: string): string =
      inc ruaCounter[]
      s[m.group(0)] & "if(process.platform===\"linux\")return;" & s[m.group(1)]
    )
    if ruaCounter[] > 0:
      echo &"  [OK] requestUserAttention Linux guard: {ruaCounter[]} match(es)"
      applied.add &"rua-guard({ruaCounter[]})"
    else:
      echo "  [WARN] requestUserAttention pattern not matched (non-critical)"

  # --- 4. backgroundThrottling ---
  let bgPattern = re2"""(enableBlinkFeatures:void 0,backgroundThrottling):(!1)"""
  if """backgroundThrottling:process.platform!=="linux"""" in content:
    echo "  [INFO] backgroundThrottling already patched"
    applied.add "bg-throttle(skip)"
  else:
    let bgCounter = new int
    bgCounter[] = 0
    content = content.replace(bgPattern, proc (m: RegexMatch2, s: string): string =
      inc bgCounter[]
      s[m.group(0)] & ":process.platform!==\"linux\"?!1:!0"
    )
    if bgCounter[] > 0:
      echo &"  [OK] backgroundThrottling enabled on Linux: {bgCounter[]} match(es)"
      applied.add &"bg-throttle({bgCounter[]})"
    else:
      echo "  [FAIL] backgroundThrottling pattern not matched"
      raise newException(ValueError, "fix_dock_bounce: backgroundThrottling pattern not matched")

  if applied.len == 0:
    echo "  [FAIL] No patches could be applied"
    raise newException(ValueError, "fix_dock_bounce: no patches applied")

  result = content

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_dock_bounce <path_to_index.js>"
    quit(1)
  let file = paramStr(1)
  echo "=== Patch: fix_dock_bounce ==="
  echo &"  Target: {file}"
  let input = readFile(file)
  let output = apply(input)
  if output != input:
    writeFile(file, output)
    echo "  [PASS] Applied"
  else:
    echo "  [PASS] No changes needed (already patched)"
