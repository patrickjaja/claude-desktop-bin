#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Make computer-use work on Linux by removing platform gates and providing a Linux executor.

Upstream has 3 platform gates that block computer-use on non-macOS:
  1. b7r(): process.platform==="darwin" && t.push(await t7r())
  2. ZM():  process.platform==="darwin" && featureFlag && chicagoEnabled
  3. L4r(): throws if process.platform !== "darwin" (createDarwinExecutor)

This patch:
  1. Removes the darwin gate in b7r() so t7r() runs on all platforms
  2. Extends ZM() to also return true on Linux
  3. Replaces L4r() (createDarwinExecutor) to return a Linux executor on Linux
     using xdotool (input), scrot (screenshots), xrandr (displays), xclip (clipboard)
  4. Patches ensureOsPermissions to return granted:true on Linux (skip TCC)
  5. Bypasses DWe.handleToolCall's permission wrapper (rvr/Z0r) on Linux —
     dispatches directly to executor methods, skipping app tiers, allowlists,
     per-app grants, and macOS permission dialogs

Everything else stays upstream: tool schemas, isEnabled logic, telemetry,
teach mode, session integration, allowedTools.

Usage: python3 fix_computer_use_linux.py <path_to_index.js>
"""

import sys
import os
import re


# Linux executor — implements the same interface as createDarwinExecutor's return value.
# Only the low-level operations are replaced; upstream dispatches to these methods.
#
# Note: execSync is used intentionally for xdotool/scrot/xrandr — these are
# hardcoded system commands, not user-controlled input.
LINUX_EXECUTOR_JS = r"""
(function(){
var _cp=require("child_process"),_path=require("path"),_fs=require("fs"),_os=require("os"),_electron=require("electron");
function _exec(cmd){return _cp.execSync(cmd,{encoding:"utf-8",timeout:15000}).trim()}
function _execBuf(cmd){return _cp.execSync(cmd,{timeout:15000})}
var _defaultMon={displayId:0,width:1920,height:1080,originX:0,originY:0,scaleFactor:1,isPrimary:true,label:"default"};
function _getMonitors(){
  try{
    var out=_exec("xrandr --current 2>/dev/null");
    var mons=[],id=0;
    var lines=out.split("\n");
    for(var i=0;i<lines.length;i++){
      var line=lines[i];
      if(line.indexOf(" connected")===-1)continue;
      var m=line.match(/(\d+)x(\d+)\+(\d+)\+(\d+)/);
      if(!m)continue;
      var label=line.split(" ")[0];
      mons.push({displayId:id++,width:+m[1],height:+m[2],originX:+m[3],originY:+m[4],scaleFactor:1,isPrimary:line.indexOf("primary")!==-1,label:label});
    }
    return mons.length>0?mons:[_defaultMon];
  }catch(e){return[_defaultMon]}
}
function _findMon(displayId){
  var mons=_getMonitors();
  if(displayId!=null){for(var i=0;i<mons.length;i++){if(mons[i].displayId===displayId)return mons[i]}}
  return mons[0];
}
function _moveMouse(x,y){_exec("xdotool mousemove --sync "+Math.round(x)+" "+Math.round(y))}
function _mapKey(k){
  var l=k.trim().toLowerCase();
  if(l==="ctrl"||l==="control")return"ctrl";
  if(l==="alt")return"alt";if(l==="shift")return"shift";
  if(l==="super"||l==="meta"||l==="cmd"||l==="command")return"super";
  if(l==="enter"||l==="return")return"Return";
  if(l==="backspace")return"BackSpace";
  if(l==="delete")return"Delete";
  if(l==="escape"||l==="esc")return"Escape";
  if(l==="tab")return"Tab";
  if(l==="space"||l===" ")return"space";
  if(l==="up")return"Up";if(l==="down")return"Down";
  if(l==="left")return"Left";if(l==="right")return"Right";
  if(l==="home")return"Home";if(l==="end")return"End";
  if(l==="pageup")return"Prior";if(l==="pagedown")return"Next";
  if(l==="capslock")return"Caps_Lock";
  return k.trim();
}
function _screenshotMon(mon){
  var tmp=_path.join(_os.tmpdir(),"claude-cu-"+Date.now()+"-"+Math.random().toString(36).slice(2)+".png");
  try{
    _cp.execSync("scrot -a "+mon.originX+","+mon.originY+","+mon.width+","+mon.height+" -o \""+tmp+"\"",{timeout:10000});
    var buf=_fs.readFileSync(tmp);try{_fs.unlinkSync(tmp)}catch(ue){}
    return buf.toString("base64");
  }catch(e){
    try{
      _cp.execSync("import -window root -crop "+mon.width+"x"+mon.height+"+"+mon.originX+"+"+mon.originY+" \""+tmp+"\"",{timeout:10000});
      var buf=_fs.readFileSync(tmp);try{_fs.unlinkSync(tmp)}catch(ue){}
      return buf.toString("base64");
    }catch(e2){throw new Error("Screenshot failed: "+e2.message)}
  }
}
function _getWinInfo(wid){
  try{
    var cls=_exec("xdotool getwindowclassname "+wid);
    var name=_exec("xdotool getwindowname "+wid);
    return{bundleId:cls,displayName:name||cls};
  }catch(e){return null}
}
globalThis.__linuxExecutor={
  capabilities:{screenshotFiltering:"none",platform:"linux",hostBundleId:"claude-desktop"},
  async listDisplays(){return _getMonitors()},
  async getDisplaySize(displayId){
    var m=_findMon(displayId);
    return{width:m.width,height:m.height,scaleFactor:m.scaleFactor};
  },
  async screenshot(opts){
    var mon=_findMon(opts&&opts.displayId);
    var b64=_screenshotMon(mon);
    return{base64:b64};
  },
  async resolvePrepareCapture(opts){
    var did=opts&&opts.preferredDisplayId;
    var mon=_findMon(did);
    var b64=_screenshotMon(mon);
    return{base64:b64,width:mon.width,height:mon.height,displayWidth:mon.width,displayHeight:mon.height,displayId:mon.displayId,originX:mon.originX,originY:mon.originY,hidden:[]};
  },
  async zoom(rect,scale,displayId){
    var tmp=_path.join(_os.tmpdir(),"claude-cu-zoom-"+Date.now()+"-"+Math.random().toString(36).slice(2)+".png");
    try{
      _cp.execSync("import -window root -crop "+rect.w+"x"+rect.h+"+"+rect.x+"+"+rect.y+" \""+tmp+"\"",{timeout:10000});
      var buf=_fs.readFileSync(tmp);try{_fs.unlinkSync(tmp)}catch(ue){}
      return{base64:buf.toString("base64")};
    }catch(e){throw new Error("Zoom failed: "+e.message)}
  },
  async prepareForAction(bundleIds,displayId){return[]},
  async previewHideSet(bundleIds,displayId){return[]},
  async findWindowDisplays(bundleIds){return[]},
  async listInstalledApps(){
    var apps=[];
    try{
      var dirs=["/usr/share/applications",_path.join(_os.homedir(),".local/share/applications")];
      for(var d=0;d<dirs.length;d++){
        try{
          var files=_fs.readdirSync(dirs[d]);
          for(var i=0;i<files.length;i++){
            if(files[i].indexOf(".desktop")===-1)continue;
            try{
              var fp=_path.join(dirs[d],files[i]);
              var content=_fs.readFileSync(fp,"utf-8");
              var nameMatch=content.match(/^Name=(.+)$/m);
              var execMatch=content.match(/^Exec=(\S+)/m);
              if(nameMatch&&execMatch){
                var id=execMatch[1].replace(/%.*/,"").trim();
                apps.push({bundleId:id,displayName:nameMatch[1],path:fp});
              }
            }catch(fe){}
          }
        }catch(de){}
      }
    }catch(e){}
    return apps;
  },
  async listRunningApps(){
    var apps=[];
    try{
      var out=_exec("wmctrl -l 2>/dev/null||xdotool search --onlyvisible --name \"\" getwindowname 2>/dev/null||true");
      var lines=out.split("\n");
      var seen={};
      for(var i=0;i<lines.length;i++){
        var line=lines[i].trim();if(!line)continue;
        var parts=line.split(/\s+/);
        if(parts.length>=5){
          var wid=parts[0];
          try{
            var cls=_exec("xdotool getwindowclassname "+wid+" 2>/dev/null");
            var title=parts.slice(4).join(" ");
            if(!seen[cls]){seen[cls]=true;apps.push({bundleId:cls,displayName:title||cls})}
          }catch(we){
            var title=parts.slice(4).join(" ");
            if(title&&!seen[title]){seen[title]=true;apps.push({bundleId:title,displayName:title})}
          }
        }
      }
    }catch(e){}
    return apps;
  },
  async getFrontmostApp(){
    try{
      var wid=_exec("xdotool getactivewindow");
      return _getWinInfo(wid);
    }catch(e){return null}
  },
  async appUnderPoint(x,y){
    try{
      var oldPos=_electron.screen.getCursorScreenPoint();
      _moveMouse(x,y);
      var locOut=_exec("xdotool getmouselocation --shell 2>/dev/null");
      var wMatch=locOut.match(/WINDOW=(\d+)/);
      _moveMouse(oldPos.x,oldPos.y);
      if(wMatch){return _getWinInfo(wMatch[1])}
      return null;
    }catch(e){return null}
  },
  async getAppIcon(appPath){return null},
  async openApp(name){
    try{
      _cp.exec("setsid "+name+" >/dev/null 2>&1");
    }catch(e){
      try{
        _cp.exec("setsid xdg-open "+name+" >/dev/null 2>&1");
      }catch(e2){throw new Error("Could not open "+name)}
    }
  },
  async moveMouse(x,y){_moveMouse(x,y)},
  async click(x,y,button,count,holdKeys){
    _moveMouse(x,y);
    var btn={left:1,right:3,middle:2}[button]||1;
    var rep=count||1;
    if(holdKeys&&holdKeys.length>0){
      for(var i=0;i<holdKeys.length;i++)_exec("xdotool keydown "+_mapKey(holdKeys[i]));
      _exec("xdotool click --repeat "+rep+" --delay 50 "+btn);
      for(var i=0;i<holdKeys.length;i++)_exec("xdotool keyup "+_mapKey(holdKeys[i]));
    }else{
      _exec("xdotool click --repeat "+rep+" --delay 50 "+btn);
    }
  },
  async mouseDown(){_exec("xdotool mousedown 1")},
  async mouseUp(){_exec("xdotool mouseup 1")},
  async getCursorPosition(){
    var p=_electron.screen.getCursorScreenPoint();
    return{x:p.x,y:p.y};
  },
  async drag(start,end){
    if(start)_moveMouse(start.x,start.y);
    _exec("xdotool mousedown 1");
    _exec("xdotool mousemove --sync "+Math.round(end.x)+" "+Math.round(end.y));
    _cp.execSync("sleep 0.05");
    _exec("xdotool mouseup 1");
  },
  async scroll(x,y,horizontal,vertical){
    _moveMouse(x,y);
    if(vertical&&vertical!==0){var vb=vertical>0?5:4;_exec("xdotool click --repeat "+Math.abs(Math.round(vertical))+" --delay 30 "+vb)}
    if(horizontal&&horizontal!==0){var hb=horizontal>0?7:6;_exec("xdotool click --repeat "+Math.abs(Math.round(horizontal))+" --delay 30 "+hb)}
  },
  async key(combo,count){
    var mapped=combo.split("+").map(_mapKey).join("+");
    var n=count||1;
    for(var i=0;i<n;i++){if(i>0)_cp.execSync("sleep 0.008");_exec("xdotool key --clearmodifiers "+mapped)}
  },
  async holdKey(keyName,seconds){
    var k=_mapKey(keyName);
    _exec("xdotool keydown "+k);
    _cp.execSync("sleep "+Math.min(seconds||0.5,10));
    _exec("xdotool keyup "+k);
  },
  async type(text,opts){
    if(opts&&opts.viaClipboard){
      var proc=_cp.spawnSync("xclip",["-selection","clipboard"],{input:text,timeout:5000});
      if(proc.status!==0){_cp.spawnSync("xsel",["--clipboard","--input"],{input:text,timeout:5000})}
      _exec("xdotool key --clearmodifiers ctrl+v");
    }else{
      _cp.execSync("xdotool type --clearmodifiers -- "+JSON.stringify(text),{timeout:15000});
    }
  },
  async readClipboard(){
    try{return _exec("xclip -selection clipboard -o 2>/dev/null||xsel --clipboard --output 2>/dev/null")}
    catch(e){return""}
  },
  async writeClipboard(text){
    var proc=_cp.spawnSync("xclip",["-selection","clipboard"],{input:text,timeout:5000});
    if(proc.status!==0){_cp.spawnSync("xsel",["--clipboard","--input"],{input:text,timeout:5000})}
  }
};
})();
"""


# Linux direct handler for DWe.handleToolCall — bypasses the rvr()/Z0r() permission
# wrapper entirely. On Linux xdotool can freely interact with any window, so the
# macOS-specific permission model (TCC, app tiers, allowlists, per-app grants)
# is meaningless. This dispatches directly to globalThis.__linuxExecutor methods.
# __SELF__ is replaced at patch time with the actual object variable name (e.g. DWe).
LINUX_DIRECT_HANDLER_JS = r"""async(t,e,r)=>{
var ex=globalThis.__linuxExecutor;
if(!ex)return{content:[{type:"text",text:"Linux executor not initialized"}],isError:!0};
try{switch(t){
case"screenshot":{var ss=await ex.screenshot({displayId:e.display_number||e.display_id||0});return{content:[{type:"image",data:ss.base64,mimeType:"image/png"}]}}
case"zoom":{var c=e.coordinate||[960,540],sz=e.size||400,hf=Math.floor(sz/2),zr=await ex.zoom({x:Math.max(0,c[0]-hf),y:Math.max(0,c[1]-hf),w:sz,h:sz},1,0);return{content:[{type:"image",data:zr.base64,mimeType:"image/png"}]}}
case"left_click":{var c=e.coordinate||[e.x,e.y];await ex.click(c[0],c[1],"left",1);return{content:[{type:"text",text:"Clicked at ("+c[0]+","+c[1]+")"}]}}
case"right_click":{var c=e.coordinate||[e.x,e.y];await ex.click(c[0],c[1],"right",1);return{content:[{type:"text",text:"Right clicked"}]}}
case"double_click":{var c=e.coordinate||[e.x,e.y];await ex.click(c[0],c[1],"left",2);return{content:[{type:"text",text:"Double clicked"}]}}
case"triple_click":{var c=e.coordinate||[e.x,e.y];await ex.click(c[0],c[1],"left",3);return{content:[{type:"text",text:"Triple clicked"}]}}
case"middle_click":{var c=e.coordinate||[e.x,e.y];await ex.click(c[0],c[1],"middle",1);return{content:[{type:"text",text:"Middle clicked"}]}}
case"type":{await ex.type(e.text||"",{viaClipboard:!1});return{content:[{type:"text",text:"Typed text"}]}}
case"key":{await ex.key(e.key||e.text||"",e.count||1);return{content:[{type:"text",text:"Pressed key: "+(e.key||e.text)}]}}
case"scroll":{var c=e.coordinate||[e.x||0,e.y||0],dir=e.scroll_direction||e.direction||"down",amt=e.scroll_amount||e.amount||3,sv=dir==="down"?amt:dir==="up"?-amt:0,sh=dir==="right"?amt:dir==="left"?-amt:0;await ex.scroll(c[0],c[1],sh,sv);return{content:[{type:"text",text:"Scrolled "+dir}]}}
case"cursor_position":{var cp=await ex.getCursorPosition();return{content:[{type:"text",text:"("+cp.x+", "+cp.y+")"}]}}
case"wait":{var ws=Math.min(e.duration||e.seconds||1,30);await new Promise(function(rv){setTimeout(rv,ws*1000)});return{content:[{type:"text",text:"Waited "+ws+"s"}]}}
case"left_click_drag":{var sc=e.start_coordinate,en=e.coordinate;await ex.drag(sc?{x:sc[0],y:sc[1]}:void 0,{x:en[0],y:en[1]});return{content:[{type:"text",text:"Dragged"}]}}
case"mouse_move":{var c=e.coordinate||[e.x,e.y];await ex.moveMouse(c[0],c[1]);return{content:[{type:"text",text:"Moved to ("+c[0]+","+c[1]+")"}]}}
case"hold_key":{await ex.holdKey(e.key||"",e.duration||.5);return{content:[{type:"text",text:"Held key"}]}}
case"left_mouse_down":{await ex.mouseDown();return{content:[{type:"text",text:"Mouse down"}]}}
case"left_mouse_up":{await ex.mouseUp();return{content:[{type:"text",text:"Mouse up"}]}}
case"open_application":{await ex.openApp(e.app||e.application||"");return{content:[{type:"text",text:"Opened app"}]}}
case"switch_display":{return{content:[{type:"text",text:"Display switching not available on Linux"}]}}
case"list_granted_applications":{return{content:[{type:"text",text:"All applications are accessible on Linux (no grants needed)"}]}}
case"read_clipboard":{var cb=await ex.readClipboard();return{content:[{type:"text",text:cb}]}}
case"write_clipboard":{await ex.writeClipboard(e.text||"");return{content:[{type:"text",text:"Written to clipboard"}]}}
case"request_access":{return{content:[{type:"text",text:"Access granted for all applications. Linux does not require per-app permission grants. You can now use screenshot, click, type, and all other computer-use tools freely."}]}}
case"computer_batch":{var actions=e.actions||[],results=[];for(var bi=0;bi<actions.length;bi++){var ba=actions[bi];results.push(await __SELF__.handleToolCall(ba.type||ba.action,ba,r))}return results.length>0?results[results.length-1]:{content:[{type:"text",text:"Batch complete"}]}}
default:return{content:[{type:"text",text:"Unknown tool: "+t}],isError:!0}
}}catch(err){return{content:[{type:"text",text:"Error: "+err.message}],isError:!0}}
}"""


def patch_computer_use_linux(filepath):
    """Make computer-use work on Linux by patching platform gates + providing Linux executor."""

    print("=== Patch: fix_computer_use_linux ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content
    changes = 0

    # Patch 1: Inject Linux executor at app.on("ready")
    inject_js = LINUX_EXECUTOR_JS.strip().encode('utf-8')
    ready_pattern = rb'(app\.on\("ready",async\(\)=>\{)'

    def inject_at_ready(m):
        return m.group(1) + b'if(process.platform==="linux"){' + inject_js + b'}'

    content, count = re.subn(ready_pattern, inject_at_ready, content, count=1)
    if count >= 1:
        print(f"  [OK] Linux executor: injected ({count} match)")
        changes += count
    else:
        print('  [FAIL] app.on("ready") pattern: 0 matches')
        return False

    # Patch 2: Remove darwin gate in b7r() — let t7r() run on all platforms
    # Original: process.platform==="darwin"&&t.push(await t7r())
    # New: always push t7r()
    darwin_gate = rb'process\.platform==="darwin"&&(\w+)\.push\(await (\w+)\(\)\)'

    def always_push(m):
        arr_var = m.group(1).decode('utf-8')
        fn_var = m.group(2).decode('utf-8')
        return f'{arr_var}.push(await {fn_var}())'.encode('utf-8')

    content, count = re.subn(darwin_gate, always_push, content, count=1)
    if count >= 1:
        print(f"  [OK] b7r() gate: removed darwin-only ({count} match)")
        changes += count
    else:
        print("  [FAIL] b7r() darwin gate: 0 matches")
        return False

    # Patch 3: Extend ZM() to include Linux — bypass feature flag + preference on Linux
    # Original: function ZM(){return process.platform==="darwin"&&_2e()&&jr("chicagoEnabled")}
    # New: On Linux, return true unconditionally (feature flag _2e() and chicagoEnabled
    #      are controlled by Anthropic's server; on Linux we enable it ourselves).
    #      On macOS, keep the original behavior.
    zm_pattern = rb'(function \w+\(\)\{return )(process\.platform==="darwin"&&\w+\(\)&&\w+\("chicagoEnabled"\))'

    def extend_zm(m):
        return m.group(1) + b'(process.platform==="linux"?!0:' + m.group(2) + b')'

    content, count = re.subn(zm_pattern, extend_zm, content, count=1)
    if count >= 1:
        print(f"  [OK] ZM(): Linux always-on, macOS unchanged ({count} match)")
        changes += count
    else:
        print("  [WARN] ZM() pattern: 0 matches (may need manual check)")

    # Patch 4: Patch createDarwinExecutor (L4r) to return Linux executor on Linux
    # Original: function L4r(t){if(process.platform!=="darwin")throw new Error(...)
    # New: function L4r(t){if(process.platform==="linux"&&globalThis.__linuxExecutor)return globalThis.__linuxExecutor;if(process.platform!=="darwin")throw...
    executor_pattern = rb'(function \w+\(\w+\)\{)if\(process\.platform!=="darwin"\)throw new Error'

    def patch_executor(m):
        return (
            m.group(1) +
            b'if(process.platform==="linux"&&globalThis.__linuxExecutor)return globalThis.__linuxExecutor;' +
            b'if(process.platform!=="darwin")throw new Error'
        )

    content, count = re.subn(executor_pattern, patch_executor, content, count=1)
    if count >= 1:
        print(f"  [OK] createDarwinExecutor: Linux fallback ({count} match)")
        changes += count
    else:
        print("  [FAIL] createDarwinExecutor pattern: 0 matches")
        return False

    # Patch 5: Patch ensureOsPermissions to return granted:true on Linux
    # Original: ensureOsPermissions:JLr  (JLr calls claude-swift TCC checks)
    # New: on Linux, return {granted:true} — no TCC permissions needed
    perms_pattern = rb'ensureOsPermissions:(\w+)'

    def patch_perms(m):
        fn_name = m.group(1).decode('utf-8')
        return (
            f'ensureOsPermissions:process.platform==="linux"'
            f'?async()=>({{granted:!0}}):{fn_name}'
        ).encode('utf-8')

    content, count = re.subn(perms_pattern, patch_perms, content, count=1)
    if count >= 1:
        print(f"  [OK] ensureOsPermissions: skip TCC on Linux ({count} match)")
        changes += count
    else:
        print("  [WARN] ensureOsPermissions pattern: 0 matches")

    # Patch 6: Bypass permission wrapper on Linux for handleToolCall
    # The upstream DWe.handleToolCall goes through rvr() which creates a permission-
    # wrapped dispatcher (Z0r). Z0r checks: TCC permissions, app tiers/allowlists,
    # CU lock, sub-gates — all macOS-specific. On Linux, we dispatch directly to
    # the executor methods via globalThis.__linuxExecutor, skipping everything.
    #
    # Pattern: VARNAME={isEnabled:FN,handleToolCall:async(t,e,r)=>{
    # Replace: VARNAME={isEnabled:FN,handleToolCall:process.platform==="linux"?LINUX_HANDLER:async(t,e,r)=>{
    dwe_pattern = rb'((\w+)=\{isEnabled:\w+=>\w+\(\),handleToolCall:)(async\(\w+,\w+,\w+\)=>\{)'

    def patch_dwe_handler(m):
        prefix = m.group(1)          # e.g. DWe={isEnabled:t=>ZM(),handleToolCall:
        obj_name = m.group(2).decode('utf-8')  # e.g. DWe
        original_start = m.group(3)  # async(t,e,r)=>{
        handler_js = LINUX_DIRECT_HANDLER_JS.strip().replace('__SELF__', obj_name)
        return (
            prefix +
            b'process.platform==="linux"?' +
            handler_js.encode('utf-8') +
            b':' +
            original_start
        )

    content, count = re.subn(dwe_pattern, patch_dwe_handler, content, count=1)
    if count >= 1:
        print(f"  [OK] handleToolCall: Linux direct dispatch, bypass permissions ({count} match)")
        changes += count
    else:
        print("  [FAIL] handleToolCall (DWe) pattern: 0 matches")
        return False

    if changes > 0 and content != original_content:
        with open(filepath, 'wb') as f:
            f.write(content)
        print(f"  [PASS] {changes} sub-patches applied")
        return True
    else:
        print("  [WARN] No changes made")
        return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_computer_use_linux(sys.argv[1])
    sys.exit(0 if success else 1)
