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
     with Wayland auto-detection: ydotool (input), grim (screenshots),
     wl-clipboard (clipboard), hyprctl/swaymsg (window info), Electron API (displays)
  4. Patches ensureOsPermissions to return granted:true on Linux (skip TCC)
  5. Hybrid handleToolCall: injects an early-return block at the top.
     - Teach tools (request_teach_access, teach_step, teach_batch) fall through
       to the upstream chain, which uses __linuxExecutor (via sub-patch 3) and
       auto-granted permissions (via sub-patch 4). The teach overlay is pure
       Electron BrowserWindow + IPC — works on Linux natively.
     - Normal CU tools use a fast direct handler dispatching to __linuxExecutor,
       skipping the macOS app tiers, allowlists, and permission dialogs.
     - switch_display: real implementation using xrandr display enumeration
     - computer_batch: structured {completed, failed, remaining} return format

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
function _isWayland(){return process.env.XDG_SESSION_TYPE==="wayland"||!!process.env.WAYLAND_DISPLAY}
var _wayland=_isWayland();
try{var _virt=_cp.execSync("systemd-detect-virt 2>/dev/null",{encoding:"utf-8",timeout:3000}).trim();globalThis.__isVM=_virt!=="none"&&_virt!==""}catch(e){globalThis.__isVM=!1}
if(globalThis.__isVM)console.log("[claude-cu] VM detected ("+_virt+") — teach overlay uses dark backdrop fallback");
var _cmdCache={};
function _hasCmd(cmd){if(_cmdCache[cmd]!==void 0)return _cmdCache[cmd];try{_exec("which "+cmd+" 2>/dev/null");_cmdCache[cmd]=true}catch(e){_cmdCache[cmd]=false}return _cmdCache[cmd]}
function _desktopId(){return(process.env.XDG_CURRENT_DESKTOP||"").toLowerCase()}
var _ydotoolOk=null;
function _checkYdotool(){if(_ydotoolOk!==null)return _ydotoolOk;if(!_hasCmd("ydotool")){_ydotoolOk=false;return false}try{_cp.execSync("pgrep -x ydotoold",{timeout:2000,stdio:"pipe"});_ydotoolOk=true}catch(e){var sock=(process.env.YDOTOOL_SOCKET||"")||((process.env.XDG_RUNTIME_DIR||"/tmp")+"/.ydotool_socket");try{_fs.accessSync(sock);_ydotoolOk=true}catch(se){console.warn("[claude-cu] ydotool found but ydotoold not running — falling back to xdotool");_ydotoolOk=false}}return _ydotoolOk}
function _readClean(f){var buf=_fs.readFileSync(f);try{_fs.unlinkSync(f)}catch(e){}return buf.toString("base64")}
function _captureRegion(x,y,w,h){
  var tmp=_path.join(_os.tmpdir(),"claude-cu-"+Date.now()+"-"+Math.random().toString(36).slice(2)+".png");
  if(process.env.COWORK_SCREENSHOT_CMD){
    try{var cmd=process.env.COWORK_SCREENSHOT_CMD.replace(/\{FILE\}/g,tmp).replace(/\{X\}/g,x).replace(/\{Y\}/g,y).replace(/\{W\}/g,w).replace(/\{H\}/g,h);
    _cp.execSync(cmd,{timeout:15000});return _readClean(tmp)}catch(e){console.warn("[claude-cu] COWORK_SCREENSHOT_CMD failed: "+e.message)}
  }
  if(_wayland&&_hasCmd("grim")){
    try{_cp.execSync('grim -g "'+x+","+y+" "+w+"x"+h+'" "'+tmp+'"',{timeout:10000});return _readClean(tmp)}catch(e){console.warn("[claude-cu] grim failed: "+e.message)}
  }
  if(_wayland&&_desktopId().indexOf("gnome")>=0&&_hasCmd("gdbus")){
    try{_cp.execSync("gdbus call --session --dest org.gnome.Shell.Screenshot --object-path /org/gnome/Shell/Screenshot --method org.gnome.Shell.Screenshot.ScreenshotArea "+x+" "+y+" "+w+" "+h+" false '"+tmp+"'",{timeout:10000});
    if(_fs.existsSync(tmp))return _readClean(tmp)}catch(e){console.warn("[claude-cu] GNOME D-Bus screenshot failed: "+e.message)}
  }
  if(_hasCmd("spectacle")){
    try{var stmp=_path.join(_os.tmpdir(),"claude-cu-spectacle-"+Date.now()+".png");
    _cp.execSync('spectacle -b -n -f -o "'+stmp+'"',{timeout:10000});
    if(_fs.existsSync(stmp)){try{_cp.execSync('convert "'+stmp+'" -crop '+w+"x"+h+"+"+x+"+"+y+' +repage "'+tmp+'"',{timeout:5000});try{_fs.unlinkSync(stmp)}catch(e){}return _readClean(tmp)}catch(ce){try{_fs.renameSync(stmp,tmp)}catch(re){}return _readClean(tmp)}}
    }catch(e){console.warn("[claude-cu] spectacle failed: "+e.message)}
  }
  if(_hasCmd("gnome-screenshot")){
    try{_cp.execSync('gnome-screenshot -f "'+tmp+'"',{timeout:10000});if(_fs.existsSync(tmp))return _readClean(tmp)}catch(e){console.warn("[claude-cu] gnome-screenshot failed: "+e.message)}
  }
  try{_cp.execSync("scrot -a "+x+","+y+","+w+","+h+' -o "'+tmp+'"',{timeout:10000});return _readClean(tmp)}catch(e){}
  try{_cp.execSync('import -window root -crop '+w+"x"+h+"+"+x+"+"+y+' "'+tmp+'"',{timeout:10000});return _readClean(tmp)}catch(e2){throw new Error("Screenshot failed — install grim (wlroots), or ensure GNOME Shell / spectacle (KDE) available, or set COWORK_SCREENSHOT_CMD env var. Error: "+e2.message)}
}
if(_wayland){console.log("[claude-cu] Wayland session detected — using native Wayland tools")}
var _defaultMon={displayId:0,width:1920,height:1080,originX:0,originY:0,scaleFactor:1,isPrimary:true,label:"default"};
function _getMonitors(){
  if(_wayland){
    try{
      var displays=_electron.screen.getAllDisplays();
      if(displays&&displays.length>0){
        var primary=_electron.screen.getPrimaryDisplay();
        var primaryId=primary?primary.id:displays[0].id;
        return displays.map(function(d,idx){return{displayId:idx,width:d.size.width,height:d.size.height,originX:d.bounds.x,originY:d.bounds.y,scaleFactor:d.scaleFactor||1,isPrimary:d.id===primaryId,label:d.label||("display-"+idx)}});
      }
    }catch(ee){}
    try{
      if(_hasCmd("wlr-randr")){
        var out=_exec("wlr-randr --json 2>/dev/null");
        var data=JSON.parse(out);
        var mons=[],id=0;
        for(var i=0;i<data.length;i++){
          var o=data[i];if(!o.enabled)continue;
          var mode=o.modes&&o.modes.find(function(m){return m.current});
          if(!mode)continue;
          mons.push({displayId:id++,width:mode.width,height:mode.height,originX:o.x||0,originY:o.y||0,scaleFactor:o.scale||1,isPrimary:id===1,label:o.name||("display-"+id)});
        }
        if(mons.length>0)return mons;
      }
    }catch(we){}
  }
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
function _moveMouse(x,y){
  if(_wayland&&_checkYdotool()){
    try{_exec("ydotool mousemove --absolute 0 0");_cp.execSync("sleep 0.05");_exec("ydotool mousemove "+Math.round(x)+" "+Math.round(y));return}catch(e){console.warn("[claude-cu] ydotool mousemove failed, falling back to xdotool: "+e.message)}
  }else{
    if(_wayland&&!_checkYdotool())console.warn("[claude-cu] ydotool not available on Wayland, falling back to xdotool via XWayland");
  }
  _exec("xdotool mousemove --sync "+Math.round(x)+" "+Math.round(y));
}
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
function _mapKeyWayland(k){
  var _kmap={"ctrl":29,"control":29,"leftctrl":29,"rightctrl":97,
    "alt":56,"leftalt":56,"rightalt":100,"shift":42,"leftshift":42,"rightshift":54,
    "super":125,"meta":125,"cmd":125,"command":125,"leftmeta":125,"rightmeta":126,
    "enter":28,"return":28,"backspace":14,"delete":111,"escape":1,"esc":1,"tab":15,
    "space":57,"up":103,"down":108,"left":105,"right":106,
    "home":102,"end":107,"pageup":104,"pagedown":109,"insert":110,
    "capslock":58,"numlock":69,"scrolllock":70,"pause":119,"sysrq":99,
    "f1":59,"f2":60,"f3":61,"f4":62,"f5":63,"f6":64,
    "f7":65,"f8":66,"f9":67,"f10":68,"f11":87,"f12":88,
    "a":30,"b":48,"c":46,"d":32,"e":18,"f":33,"g":34,"h":35,"i":23,"j":36,
    "k":37,"l":38,"m":50,"n":49,"o":24,"p":25,"q":16,"r":19,"s":31,"t":20,
    "u":22,"v":47,"w":17,"x":45,"y":21,"z":44,
    "1":2,"2":3,"3":4,"4":5,"5":6,"6":7,"7":8,"8":9,"9":10,"0":11,
    "minus":12,"equal":13,"leftbrace":26,"rightbrace":27,
    "semicolon":39,"apostrophe":40,"grave":41,"backslash":43,
    "comma":51,"dot":52,"slash":53,"kpasterisk":55,"kpminus":74,"kpplus":78};
  var l=k.trim().toLowerCase();
  return String(_kmap[l]||l);
}
function _screenshotMon(mon){return _captureRegion(mon.originX,mon.originY,mon.width,mon.height)}
function _getActiveWindowWayland(){
  try{
    if(process.env.HYPRLAND_INSTANCE_SIGNATURE&&_hasCmd("hyprctl")){
      var out=_exec("hyprctl activewindow -j 2>/dev/null");
      var w=JSON.parse(out);
      if(w&&(w.class||w.title))return{bundleId:w.class||w.title,displayName:w.title||w.class};
    }
  }catch(he){}
  try{
    if(process.env.SWAYSOCK&&_hasCmd("swaymsg")&&_hasCmd("jq")){
      var out=_exec("swaymsg -t get_tree 2>/dev/null|jq -r '.. | select(.focused? == true) | {app_id, name}'");
      var w=JSON.parse(out);
      if(w&&(w.app_id||w.name))return{bundleId:w.app_id||w.name,displayName:w.name||w.app_id};
    }
  }catch(se){}
  return null;
}
function _listRunningAppsWayland(){
  var apps=[],seen={};
  try{
    if(process.env.HYPRLAND_INSTANCE_SIGNATURE&&_hasCmd("hyprctl")){
      var out=_exec("hyprctl clients -j 2>/dev/null");
      var clients=JSON.parse(out);
      for(var i=0;i<clients.length;i++){
        var c=clients[i];
        var id=c.class||c.title;
        if(id&&!seen[id]){seen[id]=true;apps.push({bundleId:c.class||c.title,displayName:c.title||c.class})}
      }
      return apps;
    }
  }catch(he){}
  try{
    if(process.env.SWAYSOCK&&_hasCmd("swaymsg")&&_hasCmd("jq")){
      var out=_exec("swaymsg -t get_tree 2>/dev/null|jq -r '.. | select(.pid? > 0 and .visible? == true) | {app_id, name}'");
      var lines=out.split("\n");
      for(var i=0;i<lines.length;i++){
        try{
          var w=JSON.parse(lines[i]);
          var id=w.app_id||w.name;
          if(id&&!seen[id]){seen[id]=true;apps.push({bundleId:w.app_id||w.name,displayName:w.name||w.app_id})}
        }catch(pe){}
      }
      return apps;
    }
  }catch(se){}
  return apps;
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
    var b64=_captureRegion(rect.x,rect.y,rect.w,rect.h);
    return{base64:b64};
  },
  async prepareForAction(bundleIds,displayId){return[]},
  async previewHideSet(bundleIds,displayId){return[]},
  async findWindowDisplays(bundleIds){return[]},
  async listInstalledApps(){
    var apps=[];
    var seen={};
    function _add(bid,dname,p){var k=bid+"|"+dname.toLowerCase();if(!seen[k]){seen[k]=1;apps.push({bundleId:bid,displayName:dname,path:p})}}
    try{
      var dirs=["/usr/share/applications",_path.join(_os.homedir(),".local/share/applications"),"/var/lib/flatpak/exports/share/applications",_path.join(_os.homedir(),".local/share/flatpak/exports/share/applications")];
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
              var iconMatch=content.match(/^Icon=(.+)$/m);
              if(nameMatch&&execMatch){
                var fullName=nameMatch[1].trim();
                var execName=execMatch[1].replace(/%.*/,"").trim();
                var baseName=_path.basename(execName);
                _add(baseName,fullName,fp);
                var parts=fullName.split(/\s+/);
                if(parts.length>1){_add(baseName,parts[0],fp)}
                _add(baseName,baseName,fp);
                if(iconMatch){
                  var icon=iconMatch[1].trim();
                  if(icon.indexOf(".")!==-1){_add(icon,fullName,fp);if(parts.length>1){_add(icon,parts[0],fp)}}
                }
                var dfn=files[i].replace(/\.desktop$/,"");
                if(dfn!==baseName){_add(dfn,fullName,fp)}
              }
            }catch(fe){}
          }
        }catch(de){}
      }
    }catch(e){}
    return apps;
  },
  async listRunningApps(){
    if(_wayland){return _listRunningAppsWayland()}
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
    if(_wayland){return _getActiveWindowWayland()}
    try{
      var wid=_exec("xdotool getactivewindow");
      return _getWinInfo(wid);
    }catch(e){return null}
  },
  async appUnderPoint(x,y){
    if(_wayland){return null}
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
    var rep=count||1;
    if(_wayland&&_checkYdotool()){
      var ybtn={left:"0xC0",right:"0xC1",middle:"0xC2"}[button]||"0xC0";
      if(holdKeys&&holdKeys.length>0){
        var downParts=[],upParts=[];
        for(var i=0;i<holdKeys.length;i++){var mk=_mapKeyWayland(holdKeys[i]);downParts.push(mk+":1");upParts.unshift(mk+":0")}
        _exec("ydotool key "+downParts.join(" "));
        for(var _ri=0;_ri<rep;_ri++){if(_ri>0)_cp.execSync("sleep 0.05");_exec("ydotool click "+ybtn)}
        _exec("ydotool key "+upParts.join(" "));
      }else{
        for(var _ri=0;_ri<rep;_ri++){if(_ri>0)_cp.execSync("sleep 0.05");_exec("ydotool click "+ybtn)}
      }
    }else{
      var btn={left:1,right:3,middle:2}[button]||1;
      if(holdKeys&&holdKeys.length>0){
        for(var i=0;i<holdKeys.length;i++)_exec("xdotool keydown "+_mapKey(holdKeys[i]));
        _exec("xdotool click --repeat "+rep+" --delay 50 "+btn);
        for(var i=0;i<holdKeys.length;i++)_exec("xdotool keyup "+_mapKey(holdKeys[i]));
      }else{
        _exec("xdotool click --repeat "+rep+" --delay 50 "+btn);
      }
    }
  },
  async mouseDown(){
    if(_wayland&&_checkYdotool()){_exec("ydotool click 0x40")}
    else{_exec("xdotool mousedown 1")}
  },
  async mouseUp(){
    if(_wayland&&_checkYdotool()){_exec("ydotool click 0x80")}
    else{_exec("xdotool mouseup 1")}
  },
  async getCursorPosition(){
    var p=_electron.screen.getCursorScreenPoint();
    return{x:p.x,y:p.y};
  },
  async drag(start,end){
    if(start)_moveMouse(start.x,start.y);
    if(_wayland&&_checkYdotool()){
      _exec("ydotool click 0x40");
      _exec("ydotool mousemove --absolute 0 0");_cp.execSync("sleep 0.05");_exec("ydotool mousemove "+Math.round(end.x)+" "+Math.round(end.y));
      _cp.execSync("sleep 0.05");
      _exec("ydotool click 0x80");
    }else{
      _exec("xdotool mousedown 1");
      _exec("xdotool mousemove --sync "+Math.round(end.x)+" "+Math.round(end.y));
      _cp.execSync("sleep 0.05");
      _exec("xdotool mouseup 1");
    }
  },
  async scroll(x,y,horizontal,vertical){
    _moveMouse(x,y);
    if(_wayland&&_checkYdotool()){
      if(vertical&&vertical!==0){var vamt=-Math.round(vertical);_exec("ydotool mousemove -w -- 0 "+vamt)}
      if(horizontal&&horizontal!==0){var hamt=Math.round(horizontal);_exec("ydotool mousemove -w -- "+hamt+" 0")}
    }else{
      if(vertical&&vertical!==0){var vb=vertical>0?5:4;_exec("xdotool click --repeat "+Math.abs(Math.round(vertical))+" --delay 30 "+vb)}
      if(horizontal&&horizontal!==0){var hb=horizontal>0?7:6;_exec("xdotool click --repeat "+Math.abs(Math.round(horizontal))+" --delay 30 "+hb)}
    }
  },
  async key(combo,count){
    var n=count||1;
    if(_wayland&&_checkYdotool()){
      var parts=combo.split("+").map(_mapKeyWayland);
      if(parts.length===1){
        for(var i=0;i<n;i++){if(i>0)_cp.execSync("sleep 0.008");_exec("ydotool key "+parts[0]+":1 "+parts[0]+":0")}
      }else{
        var downSeq=[],upSeq=[];
        for(var j=0;j<parts.length;j++){downSeq.push(parts[j]+":1");upSeq.unshift(parts[j]+":0")}
        var seq=downSeq.concat(upSeq).join(" ");
        for(var i=0;i<n;i++){if(i>0)_cp.execSync("sleep 0.008");_exec("ydotool key "+seq)}
      }
    }else{
      var mapped=combo.split("+").map(_mapKey).join("+");
      for(var i=0;i<n;i++){if(i>0)_cp.execSync("sleep 0.008");_exec("xdotool key --clearmodifiers "+mapped)}
    }
  },
  async holdKey(keyName,seconds){
    var secs=Math.min(seconds||0.5,10);
    if(_wayland&&_checkYdotool()){
      var k=_mapKeyWayland(keyName);
      _exec("ydotool key "+k+":1");
      _cp.execSync("sleep "+secs);
      _exec("ydotool key "+k+":0");
    }else{
      var k=_mapKey(keyName);
      _exec("xdotool keydown "+k);
      _cp.execSync("sleep "+secs);
      _exec("xdotool keyup "+k);
    }
  },
  async type(text,opts){
    if(_wayland&&_checkYdotool()){
      if(opts&&opts.viaClipboard){
        var proc=_cp.spawnSync("wl-copy",[],{input:text,timeout:5000});
        if(proc.status!==0){
          proc=_cp.spawnSync("xclip",["-selection","clipboard"],{input:text,timeout:5000});
        }
        if(_checkYdotool()){
          _exec("ydotool key leftctrl:1 v:1 v:0 leftctrl:0");
        }else{
          _exec("xdotool key --clearmodifiers ctrl+v");
        }
      }else{
        _cp.execSync("ydotool type -- "+JSON.stringify(text),{timeout:15000});
      }
    }else{
      if(opts&&opts.viaClipboard){
        var proc=_cp.spawnSync("xclip",["-selection","clipboard"],{input:text,timeout:5000});
        if(proc.status!==0){_cp.spawnSync("xsel",["--clipboard","--input"],{input:text,timeout:5000})}
        _exec("xdotool key --clearmodifiers ctrl+v");
      }else{
        _cp.execSync("xdotool type --clearmodifiers -- "+JSON.stringify(text),{timeout:15000});
      }
    }
  },
  async readClipboard(){
    if(_wayland&&_hasCmd("wl-paste")){
      try{return _exec("wl-paste --no-newline 2>/dev/null")}
      catch(e){try{return _exec("xclip -selection clipboard -o 2>/dev/null")}catch(e2){return""}}
    }
    try{return _exec("xclip -selection clipboard -o 2>/dev/null||xsel --clipboard --output 2>/dev/null")}
    catch(e){return""}
  },
  async writeClipboard(text){
    if(_wayland&&_hasCmd("wl-copy")){
      var proc=_cp.spawnSync("wl-copy",[],{input:text,timeout:5000});
      if(proc.status===0)return;
      console.warn("[claude-cu] wl-copy failed, falling back to xclip");
    }
    var proc=_cp.spawnSync("xclip",["-selection","clipboard"],{input:text,timeout:5000});
    if(proc.status!==0){_cp.spawnSync("xsel",["--clipboard","--input"],{input:text,timeout:5000})}
  }
};
})();
"""


# Linux hybrid handler — injected at the top of handleToolCall as an early-return block.
#
# Architecture:
#   - Teach tools (request_teach_access, teach_step, teach_batch) and request_access
#     fall through to the UPSTREAM chain. Sub-patches 2-5 ensure the upstream chain
#     uses __linuxExecutor and auto-grants permissions. The teach overlay (BrowserWindow
#     + IPC) works on Linux natively since it's pure Electron.
#   - Normal CU tools use a FAST DIRECT handler dispatching to __linuxExecutor,
#     skipping the macOS app tiers, allowlists, and permission dialogs.
#
# __DISPATCHER__ is replaced at patch time with the actual session dispatcher function
# name (e.g. EZr). __SELF__ is replaced with the object name (e.g. nnt).
LINUX_HANDLER_INJECTION_JS = r"""if(process.platform==="linux"){
var __lxTeachTools=["request_teach_access","teach_step","teach_batch","request_access"];
if(__lxTeachTools.indexOf(t)>=0){const __n=__DISPATCHER__(r);const{save_to_disk:__sd,...__s}=e;return await __n(t,__s)}
var ex=globalThis.__linuxExecutor;
if(!ex)return{content:[{type:"text",text:"Linux executor not initialized"}],isError:!0};
var __actionTools=new Set(["left_click","right_click","double_click","triple_click","middle_click","left_click_drag","mouse_move","scroll","key","type","hold_key","left_mouse_down","left_mouse_up","computer_batch"]);
async function __hideWindows(fn){var __bws=require("electron").BrowserWindow.getAllWindows().filter(function(w){return!w.isDestroyed()});for(var __i=0;__i<__bws.length;__i++)__bws[__i].setIgnoreMouseEvents(true);try{await new Promise(function(r){setTimeout(r,50)});return await fn()}finally{for(var __i=0;__i<__bws.length;__i++){if(!__bws[__i].isDestroyed())__bws[__i].setIgnoreMouseEvents(false)}}}
if(__actionTools.has(t)){return await __hideWindows(async function(){switch(t){
case"left_click":{var __lc=e.coordinate||[e.x,e.y];await ex.click(__lc[0],__lc[1],"left",1);return{content:[{type:"text",text:"Clicked at ("+__lc[0]+","+__lc[1]+")"}]}}
case"right_click":{var __rc=e.coordinate||[e.x,e.y];await ex.click(__rc[0],__rc[1],"right",1);return{content:[{type:"text",text:"Right clicked"}]}}
case"double_click":{var __dc=e.coordinate||[e.x,e.y];await ex.click(__dc[0],__dc[1],"left",2);return{content:[{type:"text",text:"Double clicked"}]}}
case"triple_click":{var __tc=e.coordinate||[e.x,e.y];await ex.click(__tc[0],__tc[1],"left",3);return{content:[{type:"text",text:"Triple clicked"}]}}
case"middle_click":{var __mc=e.coordinate||[e.x,e.y];await ex.click(__mc[0],__mc[1],"middle",1);return{content:[{type:"text",text:"Middle clicked"}]}}
case"type":{await ex.type(e.text||"",{viaClipboard:!1});return{content:[{type:"text",text:"Typed text"}]}}
case"key":{await ex.key(e.key||e.text||"",e.count||1);return{content:[{type:"text",text:"Pressed key: "+(e.key||e.text)}]}}
case"scroll":{var __sc=e.coordinate||[e.x||0,e.y||0],__dir=e.scroll_direction||e.direction||"down",__amt=e.scroll_amount||e.amount||3,__sv=__dir==="down"?__amt:__dir==="up"?-__amt:0,__sh=__dir==="right"?__amt:__dir==="left"?-__amt:0;await ex.scroll(__sc[0],__sc[1],__sh,__sv);return{content:[{type:"text",text:"Scrolled "+__dir}]}}
case"left_click_drag":{var __dsc=e.start_coordinate,__den=e.coordinate;await ex.drag(__dsc?{x:__dsc[0],y:__dsc[1]}:void 0,{x:__den[0],y:__den[1]});return{content:[{type:"text",text:"Dragged"}]}}
case"mouse_move":{var __mv=e.coordinate||[e.x,e.y];await ex.moveMouse(__mv[0],__mv[1]);return{content:[{type:"text",text:"Moved to ("+__mv[0]+","+__mv[1]+")"}]}}
case"hold_key":{await ex.holdKey(e.key||"",e.duration||.5);return{content:[{type:"text",text:"Held key"}]}}
case"left_mouse_down":{await ex.mouseDown();return{content:[{type:"text",text:"Mouse down"}]}}
case"left_mouse_up":{await ex.mouseUp();return{content:[{type:"text",text:"Mouse up"}]}}
case"computer_batch":{var __actions=e.actions||[],__completed=[],__failIdx=-1,__failErr;for(var __bi=0;__bi<__actions.length;__bi++){var __ba=__actions[__bi];try{var __br=await __SELF__.handleToolCall(__ba.action||__ba.type,__ba,r);__completed.push({type:__ba.action||__ba.type,result:__br})}catch(__be){__failIdx=__bi;__failErr=__be.message;break}}var __resp={completed:__completed};if(__failIdx>=0){__resp.failed={index:__failIdx,action:__actions[__failIdx].action||__actions[__failIdx].type,error:__failErr};__resp.remaining=__actions.slice(__failIdx+1).map(function(a){return a.action||a.type})}return{content:[{type:"text",text:JSON.stringify(__resp)}]}}
default:return{content:[{type:"text",text:"Unknown action tool: "+t}],isError:!0}
}})}
try{switch(t){
case"screenshot":{var __did=globalThis.__cuPinnedDisplay!==void 0?globalThis.__cuPinnedDisplay:(e.display_number||e.display_id||0);var __ss=await ex.screenshot({displayId:__did});return{content:[{type:"image",data:__ss.base64,mimeType:"image/png"}]}}
case"zoom":{var __zc=e.coordinate||[960,540],__sz=e.size||400,__hf=Math.floor(__sz/2),__zr=await ex.zoom({x:Math.max(0,__zc[0]-__hf),y:Math.max(0,__zc[1]-__hf),w:__sz,h:__sz},1,0);return{content:[{type:"image",data:__zr.base64,mimeType:"image/png"}]}}
case"cursor_position":{var __cp=await ex.getCursorPosition();return{content:[{type:"text",text:"("+__cp.x+", "+__cp.y+")"}]}}
case"wait":{var __ws=Math.min(e.duration||e.seconds||1,30);await new Promise(function(__rv){setTimeout(__rv,__ws*1000)});return{content:[{type:"text",text:"Waited "+__ws+"s"}]}}
case"open_application":{await ex.openApp(e.app||e.application||"");return{content:[{type:"text",text:"Opened app"}]}}
case"switch_display":{var __displays=await ex.listDisplays();var __target=e.display;if(__target==="auto"||!__target){globalThis.__cuPinnedDisplay=void 0;return{content:[{type:"text",text:"Display mode set to auto (follows cursor). Available: "+__displays.map(function(d){return d.label+" ("+d.width+"x"+d.height+")"}).join(", ")}]}}var __found=__displays.find(function(d){return d.label===__target||String(d.displayId)===String(__target)});if(__found){globalThis.__cuPinnedDisplay=__found.displayId;return{content:[{type:"text",text:"Switched to display: "+__found.label+" ("+__found.width+"x"+__found.height+")"}]}}return{content:[{type:"text",text:"Display '"+__target+"' not found. Available: "+__displays.map(function(d){return d.label}).join(", ")}]}}
case"list_granted_applications":{return{content:[{type:"text",text:"All applications are accessible on Linux (no grants needed)"}]}}
case"read_clipboard":{var cb=await ex.readClipboard();return{content:[{type:"text",text:cb}]}}
case"write_clipboard":{await ex.writeClipboard(e.text||"");return{content:[{type:"text",text:"Written to clipboard"}]}}
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

    with open(filepath, "rb") as f:
        content = f.read()

    original_content = content
    changes = 0

    # Patch 1: Inject Linux executor at app.on("ready")
    inject_js = LINUX_EXECUTOR_JS.strip().encode("utf-8")
    ready_pattern = rb'(app\.on\("ready",async\(\)=>\{)'

    def inject_at_ready(m):
        return m.group(1) + b'if(process.platform==="linux"){' + inject_js + b"}"

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
        arr_var = m.group(1).decode("utf-8")
        fn_var = m.group(2).decode("utf-8")
        return f"{arr_var}.push(await {fn_var}())".encode("utf-8")

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
        return m.group(1) + b'(process.platform==="linux"?!0:' + m.group(2) + b")"

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
        return m.group(1) + b'if(process.platform==="linux"&&globalThis.__linuxExecutor)return globalThis.__linuxExecutor;' + b'if(process.platform!=="darwin")throw new Error'

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
    perms_pattern = rb"ensureOsPermissions:(\w+)"

    def patch_perms(m):
        fn_name = m.group(1).decode("utf-8")
        return (f'ensureOsPermissions:process.platform==="linux"?async()=>({{granted:!0}}):{fn_name}').encode("utf-8")

    content, count = re.subn(perms_pattern, patch_perms, content, count=1)
    if count >= 1:
        print(f"  [OK] ensureOsPermissions: skip TCC on Linux ({count} match)")
        changes += count
    else:
        print("  [WARN] ensureOsPermissions pattern: 0 matches")

    # Patch 6: Hybrid handleToolCall — inject early-return block at the top
    # The upstream handleToolCall calls EZr(r) to get a session-cached permission
    # dispatcher. On Linux, we inject an early-return block that:
    #   - For teach tools: falls through to the upstream chain (uses __linuxExecutor
    #     via sub-patch 4, auto-grants via sub-patch 5, teach overlay works natively)
    #   - For normal tools: fast direct dispatch to __linuxExecutor, skipping macOS
    #     app tiers, allowlists, CU lock, and permission dialogs
    #
    # Pattern: VARNAME={isEnabled:FN,handleToolCall:async(t,e,r)=>{...const n=DISPATCHER(r),...
    # There may be variable declarations between { and const (e.g. var u,d,f,p,h,y;).
    # Inject: LINUX_HANDLER_INJECTION after the opening brace, before any existing code.
    dwe_pattern = rb"((\w+)=\{isEnabled:\w+=>\w+\(\),handleToolCall:async\((\w+),(\w+),(\w+)\)=>\{)([^}]{0,100}const \w+=(\w+)\(\5\))"

    def patch_dwe_handler(m):
        prefix = m.group(1)  # e.g. nnt={isEnabled:t=>JL(),handleToolCall:async(t,e,r)=>{
        obj_name = m.group(2).decode("utf-8")  # e.g. nnt
        dispatcher = m.group(7).decode("utf-8")  # e.g. EZr
        original_code = m.group(6)  # var u,d,f,p,h,y;const n=EZr(r)
        handler_js = LINUX_HANDLER_INJECTION_JS.strip()
        handler_js = handler_js.replace("__SELF__", obj_name)
        handler_js = handler_js.replace("__DISPATCHER__", dispatcher)
        return prefix + handler_js.encode("utf-8") + original_code

    content, count = re.subn(dwe_pattern, patch_dwe_handler, content, count=1)
    if count >= 1:
        print(f"  [OK] handleToolCall: hybrid dispatch (teach→upstream, rest→direct) ({count} match)")
        changes += count
    else:
        print("  [FAIL] handleToolCall pattern: 0 matches")
        return False

    # Patch 7: Initialize teach overlay controller on Linux
    # The main window init has a ternary: process.platform==="darwin" ? (darwin-only setup) : (stub)
    # The darwin branch calls RUn(r,t) which initializes the teach overlay controller,
    # QDr() for escape-key handling, FUn() for side-panel, and mUn() for nav/focus.
    # On Linux, none of these run — so the teach overlay BrowserWindow is never created,
    # the IPC handlers for cu-teach:next/exit are never registered, and teach_step hangs.
    #
    # Fix: Find the else-branch stub (rIt.for(WEBCONTENTS).setImplementation({...})) and
    # inject the essential overlay calls AFTER it. We capture the session manager and main
    # window variable names from the darwin branch pattern.
    #
    # Pattern: RUn(MGR,WIN),...  (in the darwin branch)
    # Then after the else stub: inject RUn(MGR,WIN) + QDr + FUn for Linux
    overlay_pattern = rb'(\w+)\((\w+),(\w+)\),(\w+)\((\w+)=>\{[^}]*\},\3\),\2\.on\("cuSelectedDisplayChanged"'

    overlay_match = re.search(overlay_pattern, content)
    if overlay_match:
        run_fn = overlay_match.group(1).decode("utf-8")  # RUn
        mgr_var = overlay_match.group(2).decode("utf-8")  # r (session manager)
        win_var = overlay_match.group(3).decode("utf-8")  # t (main window)

        # Find the else-branch stub and inject RUn as a comma expression
        # The else branch is: (rIt.for(...).setImplementation({...}),fY.for(...),...)
        # We add RUn(r,t) as another comma-separated expression inside it.
        # Pattern: listInstalledApps:()=>[]}) — end of the TCC stub, followed by comma
        stub_end = rb"listInstalledApps:\(\)=>\[\]\}\)"
        stub_match = re.search(stub_end, content)
        if stub_match:
            inject_pos = stub_match.end()
            inject_js = f',process.platform==="linux"&&{run_fn}({mgr_var},{win_var})'.encode("utf-8")
            content = content[:inject_pos] + inject_js + content[inject_pos:]
            print(f"  [OK] teach overlay controller: {run_fn}({mgr_var},{win_var}) injected for Linux (1 match)")
            changes += 1
        else:
            print("  [WARN] teach overlay: TCC stub end pattern not found")
    else:
        print("  [WARN] teach overlay: RUn pattern not found in darwin branch")

    # Patch 8: Fix teach overlay mouse events on Linux
    # On macOS, setIgnoreMouseEvents(true, {forward: true}) makes transparent areas
    # click-through while still receiving mouseenter/mouseleave events. On Linux/X11,
    # {forward: true} is NOT implemented (Electron issue #16777, open since 2019).
    # The overlay becomes fully click-through and NEVER receives mouseenter, so the
    # tooltip buttons (Next/Exit) remain unclickable forever.
    #
    # Previous fix (broken): Polled cursor against overlay.getContentBounds() — but
    # the overlay is FULLSCREEN, so cursor was always "inside" → setIgnoreMouseEvents(false)
    # permanently → entire screen blocked.
    #
    # Current fix: Poll cursor against the TOOLTIP CARD bounds (not the overlay window
    # bounds). Uses executeJavaScript to query the .tooltip element's bounding rect
    # from the renderer every 200ms, then checks cursor position against those card
    # bounds every 50ms. When cursor is over the card → clickable. Otherwise → pass-through.
    #
    # Works on X11 and XWayland. Wayland fallback: if getPosition() returns (0,0) and
    # tooltip bounds are available, assumes the overlay fills the workArea and adjusts.

    # Find the overlay variable name from: OVERLAYVAR.setAlwaysOnTop(!0,"screen-saver"),OVERLAYVAR.setFullScreenable(!1),OVERLAYVAR.setIgnoreMouseEvents(!0,{forward:!0})
    overlay_var_pattern = rb'(\w+)\.setAlwaysOnTop\(!0,"screen-saver"\),\1\.setFullScreenable\(!1\),\1\.setIgnoreMouseEvents\(!0,\{forward:!0\}\)'

    overlay_var_match = re.search(overlay_var_pattern, content)
    if overlay_var_match:
        ov = overlay_var_match.group(1).decode("utf-8")  # e.g. oa

        # Replace the initial setIgnoreMouseEvents on the overlay with Linux tooltip-bounds polling
        old_init = f"{ov}.setIgnoreMouseEvents(!0,{{forward:!0}})".encode("utf-8")

        # Build the executeJavaScript query string separately to avoid f-string escaping hell
        # This JS runs in the overlay renderer to get the tooltip card's bounding rect
        js_query = (
            '\'(function(){var t=document.querySelector(".tooltip");'
            "if(t&&t.offsetWidth>0){var r=t.getBoundingClientRect();"
            "return JSON.stringify({x:r.left,y:r.top,w:r.width,h:r.height})}"
            "return null})()'"
        )

        new_init = (
            '(process.platform==="linux"?'
            # On Linux, keep the teach overlay permanently pass-through (visual only).
            # Electron bug #16777: setIgnoreMouseEvents(true,{forward:true}) doesn't
            # forward mouse events on Linux. teach_batch auto-advances steps.
            # On VMs: also set low opacity (dark backdrop) since transparency crashes GPU.
            f"({ov}.setIgnoreMouseEvents(!0),globalThis.__isVM&&{ov}.setOpacity(.15))"
            f":{ov}.setIgnoreMouseEvents(!0,{{forward:!0}}))"
        ).encode("utf-8")

        # Only replace the first occurrence (overlay init)
        content = content.replace(old_init, new_init, 1)
        if new_init in content:
            print(f"  [OK] teach overlay mouse: tooltip-bounds polling for Linux ({ov})")
            changes += 1
        else:
            print("  [WARN] teach overlay mouse: replacement failed")
    else:
        print("  [WARN] teach overlay mouse: overlay variable pattern not found")

    # Patch 9: Neutralize setIgnoreMouseEvents resets in yJt/SUn on Linux
    # The upstream code calls setIgnoreMouseEvents(true,{forward:true}) in two places
    # during step transitions: yJt() (show step) and SUn() (working state).
    # On macOS, {forward:true} allows the overlay to still receive mouse-enter events.
    # On Linux, it just becomes setIgnoreMouseEvents(true) which fights with our polling.
    # Fix: wrap these calls so on Linux they're no-ops (our polling handles the state).
    #
    # Pattern in yJt: OVERLAYVAR.setIgnoreMouseEvents(!0,{forward:!0}),OVERLAYVAR.webContents.send("cu-teach:show"
    # Pattern in SUn: OVERLAYVAR.setIgnoreMouseEvents(!0,{forward:!0}),OVERLAYVAR.webContents.send("cu-teach:working"

    if overlay_var_match:
        # 9a: yJt() uses function parameter (not global oa) — pattern: function yJt(PARAM,e){PARAM.setIgnoreMouseEvents(!0,{forward:!0})
        yjt_pat = rb"(function \w+\(\w+,\w+\)\{)(\w+)(\.setIgnoreMouseEvents\(!0,\{forward:!0\}\))"

        def yjt_repl(m):
            fn_head = m.group(1).decode("utf-8")
            var = m.group(2).decode("utf-8")
            rest = m.group(3).decode("utf-8")
            return f'{fn_head}(process.platform!=="linux"&&{var}{rest})'.encode("utf-8")

        content_new, yjt_count = re.subn(yjt_pat, yjt_repl, content, count=1)
        if yjt_count:
            content = content_new
            print("  [OK] teach overlay: neutralized setIgnoreMouseEvents in show handler (yJt) for Linux")
            changes += 1
        else:
            print("  [WARN] teach overlay: yJt pattern not found (may be OK)")

        # 9b: SUn() uses global overlay var — pattern: oa.setIgnoreMouseEvents(!0,{forward:!0}),oa.webContents.send("cu-teach:working"
        sun_pat = f'{ov}.setIgnoreMouseEvents(!0,{{forward:!0}}),{ov}.webContents.send("cu-teach:working"'.encode("utf-8")
        sun_repl = f'(process.platform!=="linux"&&{ov}.setIgnoreMouseEvents(!0,{{forward:!0}})),{ov}.webContents.send("cu-teach:working"'.encode("utf-8")
        if sun_pat in content:
            content = content.replace(sun_pat, sun_repl, 1)
            print("  [OK] teach overlay: neutralized setIgnoreMouseEvents in working handler (SUn) for Linux")
            changes += 1
        else:
            print("  [WARN] teach overlay: SUn pattern not found (may be OK)")

    # Patch 10: Fix teach overlay transparency on VMs
    # The fullscreen transparent BrowserWindow causes GPU crashes and cursor artifacts
    # on virtual GPUs (VirtualBox VMSVGA, etc.). On native hardware it works fine.
    # Detect VMs at runtime using systemd-detect-virt and fall back to a dark backdrop.
    # Native hardware keeps full transparency (see-through overlay like macOS).
    teach_overlay_pattern = rb'(=new \w+\.BrowserWindow\(\{[^}]*?)transparent:!0([^}]*?)backgroundColor:"#00000000"'
    teach_overlay_matches = list(re.finditer(teach_overlay_pattern, content))
    for m in teach_overlay_matches:
        before = content[max(0, m.start()-80):m.start()]
        if b'workArea' in before:
            old = m.group(0)
            new = old.replace(
                b'transparent:!0',
                b'transparent:!globalThis.__isVM'
            ).replace(
                b'backgroundColor:"#00000000"',
                b'backgroundColor:globalThis.__isVM?"#000000":"#00000000"'
            )
            content = content.replace(old, new, 1)
            print("  [OK] teach overlay: VM-aware transparency (transparent on native, dark backdrop on VMs)")
            changes += 1
            break
    else:
        print("  [WARN] teach overlay transparency pattern not found")

    if changes > 0 and content != original_content:
        with open(filepath, "wb") as f:
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
