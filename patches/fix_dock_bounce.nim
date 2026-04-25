# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
# Suppress taskbar flashing (demands-attention) on Linux/Wayland+X11.
# Three sub-patches: early monkey-patch, steal-focus, rua-guard.

import std/[os, strformat, strutils]
import regex

const EXPECTED_PATCHES = 3

const LINUX_WAYLAND_GUARD = """;(function(){
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

proc replaceFirst(content: var string, pattern: Regex2, subFn: proc(m: RegexMatch2, s: string): string): int =
  var found = false
  var resultStr = ""
  var lastEnd = 0
  for m in content.findAll(pattern):
    if not found:
      let bounds = m.boundaries
      resultStr &= content[lastEnd ..< bounds.a]
      resultStr &= subFn(m, content)
      lastEnd = bounds.b + 1
      found = true
      break
  if found:
    resultStr &= content[lastEnd .. ^1]
    content = resultStr
    return 1
  return 0

proc apply*(input: string): string =
  result = input
  var patchesApplied = 0
  var applied: seq[string] = @[]

  # 1. Inject early monkey-patch block
  let marker = "_e.app.on(\"browser-window-blur\""
  if marker in result:
    echo "  [INFO] Early monkey-patch already injected"
    applied.add("early-guard(skip)")
    patchesApplied += 1
  else:
    # Remove old version of guard if present
    let oldMarkers = @[
      "_e.app.focus=function(){}",
      "_e.BrowserWindow.prototype.flashFrame=function(){}",
    ]
    for oldM in oldMarkers:
      if oldM in result and marker notin result:
        # Old guard removal via regex
        let oldGuardPat = re2";?\(function\(\)\{\s*if\(process\.platform===""linux""\)\{.*?\}\s*\}\)\(\);"
        var dummy = 0
        result = result.replace(oldGuardPat, proc(m: RegexMatch2, s: string): string =
          inc dummy
          ""
        )
        if dummy > 0:
          echo "  [OK] Removed old monkey-patch block"
        break

    if result.startsWith("\"use strict\";"):
      result = "\"use strict\";" & LINUX_WAYLAND_GUARD & result[len("\"use strict\";") .. ^1]
      echo "  [OK] Early monkey-patch injected after \"use strict\""
      applied.add("early-guard")
      patchesApplied += 1
    else:
      result = LINUX_WAYLAND_GUARD & result
      echo "  [OK] Early monkey-patch prepended"
      applied.add("early-guard(prepend)")
      patchesApplied += 1

  # 2. Strip steal from app.focus({steal:!0})
  let stealPattern = re2"([\w$]+\.app\.focus)\(\{steal:!?[01t][\w$]*\}\)"

  let stealAlreadyCleanPat = re2"[\w$]+\.app\.focus\(\{steal:"
  var stealAlreadyClean = true
  for m in result.findAll(stealAlreadyCleanPat):
    stealAlreadyClean = false
    break

  var stealCount = 0
  result = result.replace(stealPattern, proc(m: RegexMatch2, s: string): string =
    inc stealCount
    s[m.group(0)] & "({})"
  )
  if stealCount > 0:
    echo &"  [OK] Removed app.focus({{steal}}) calls: {stealCount} match(es)"
    applied.add(&"steal-focus({stealCount})")
    patchesApplied += 1
  elif stealAlreadyClean:
    echo "  [INFO] app.focus({steal}) already stripped"
    applied.add("steal-focus(skip)")
    patchesApplied += 1
  else:
    echo "  [FAIL] app.focus({steal}) pattern not matched"

  # 3. No-op requestUserAttention on Linux
  if "requestUserAttention(){if(process.platform===\"linux\")return;" in result:
    echo "  [INFO] requestUserAttention already guarded"
    applied.add("rua-guard(skip)")
    patchesApplied += 1
  else:
    let ruaPattern = re2"(requestUserAttention\(\)\{)(var [\w$]+;this\.isAppFocusedAndVisible\(\)\|\|)"
    var ruaCount = 0
    result = result.replace(ruaPattern, proc(m: RegexMatch2, s: string): string =
      inc ruaCount
      s[m.group(0)] & "if(process.platform===\"linux\")return;" & s[m.group(1)]
    )
    if ruaCount > 0:
      echo &"  [OK] requestUserAttention Linux guard: {ruaCount} match(es)"
      applied.add(&"rua-guard({ruaCount})")
      patchesApplied += 1
    else:
      echo "  [FAIL] requestUserAttention pattern not matched"

  # Sub-patch 4 (bg-throttle) removed: backgroundThrottling was explicitly
  # set to false by upstream but has been removed in 1.4758.0+. Electron's
  # default is true, which is the behaviour the patch intended for Linux.

  if patchesApplied < EXPECTED_PATCHES:
    raise newException(ValueError, &"fix_dock_bounce: Only {patchesApplied}/{EXPECTED_PATCHES} patches applied")

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_dock_bounce <file>"
    quit(1)
  let file = paramStr(1)
  echo "=== Patch: fix_dock_bounce ==="
  echo &"  Target: {file}"
  if not fileExists(file):
    echo &"  [FAIL] File not found: {file}"
    quit(1)
  let input = readFile(file)
  let output = apply(input)
  if output != input:
    writeFile(file, output)
    echo "  [PASS] Patches applied"
  else:
    echo "  [PASS] No changes needed (already patched)"
