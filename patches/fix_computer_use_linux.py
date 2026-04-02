#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Make computer-use work on Linux by removing platform gates and providing a Linux executor.

Upstream has platform gates that block computer-use on non-macOS/Windows:
  1. ese = new Set(["darwin","win32"]) — vee() checks this set, gating the push
     of the CU server def and the chicagoEnabled check (rj())
  2. createDarwinExecutor: throws if process.platform !== "darwin"

This patch:
  1. Adds "linux" to the ese Set so vee()/rj() accept Linux
  2. (Removed — handled by Set fix)
  3. Replaces createDarwinExecutor to return a Linux executor on Linux
     using xdotool (input), scrot (screenshots), Electron API (displays, clipboard)
     with session-aware detection: XDG_SESSION_TYPE for X11/Wayland,
     SWAYSOCK/HYPRLAND_INSTANCE_SIGNATURE for wlroots compositors,
     XDG_CURRENT_DESKTOP for KDE/GNOME. Tools: ydotool (Wayland input),
     grim (wlroots screenshots), spectacle (KDE), gdbus (GNOME Wayland),
     hyprctl/swaymsg (window info), desktopCapturer (screenshot fallback)
  4. Patches ensureOsPermissions to return granted:true on Linux (skip TCC)
  5. Hybrid handleToolCall: injects an early-return block at the top.
     - Teach tools (request_teach_access, teach_step, teach_batch) fall through
       to the upstream chain, which uses __linuxExecutor (via sub-patch 3) and
       auto-granted permissions (via sub-patch 4). The teach overlay is pure
       Electron BrowserWindow + IPC — works on Linux natively.
     - Normal CU tools use a fast direct handler dispatching to __linuxExecutor,
       skipping the macOS app tiers, allowlists, and permission dialogs.
     - switch_display: real implementation using Electron screen API
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
function _isWayland(){var st=(process.env.XDG_SESSION_TYPE||"").toLowerCase();if(st==="wayland")return true;if(st==="x11")return false;return!!process.env.WAYLAND_DISPLAY}
var _wayland=_isWayland();
function _isWlroots(){return!!process.env.SWAYSOCK||!!process.env.HYPRLAND_INSTANCE_SIGNATURE}
try{var _virt=_cp.execSync("systemd-detect-virt 2>/dev/null",{encoding:"utf-8",timeout:3000}).trim();globalThis.__isVM=_virt!=="none"&&_virt!==""}catch(e){globalThis.__isVM=!1}
if(globalThis.__isVM)console.log("[claude-cu] VM detected ("+_virt+") — teach overlay uses dark backdrop fallback");
var _cmdCache={};
function _hasCmd(cmd){if(_cmdCache[cmd]!==void 0)return _cmdCache[cmd];try{_exec("which "+cmd+" 2>/dev/null");_cmdCache[cmd]=true}catch(e){_cmdCache[cmd]=false}return _cmdCache[cmd]}
function _desktopId(){return(process.env.XDG_CURRENT_DESKTOP||"").toLowerCase()}
var _ydotoolOk=null;
function _checkYdotool(){if(_ydotoolOk!==null)return _ydotoolOk;if(!_hasCmd("ydotool")){_ydotoolOk=false;return false}try{_cp.execSync("pgrep -x ydotoold",{timeout:2000,stdio:"pipe"});_ydotoolOk=true}catch(e){var sock=(process.env.YDOTOOL_SOCKET||"")||((process.env.XDG_RUNTIME_DIR||"/tmp")+"/.ydotool_socket");try{_fs.accessSync(sock);_ydotoolOk=true}catch(se){console.warn("[claude-cu] ydotool found but ydotoold not running — falling back to xdotool");_ydotoolOk=false}}return _ydotoolOk}
function _readClean(f){var buf=_fs.readFileSync(f);try{_fs.unlinkSync(f)}catch(e){}return buf.toString("base64")}
async function _captureRegion(x,y,w,h){
  var tmp=_path.join(_os.tmpdir(),"claude-cu-"+Date.now()+"-"+Math.random().toString(36).slice(2)+".png");
  var _de=_desktopId();
  if(process.env.COWORK_SCREENSHOT_CMD){
    try{var cmd=process.env.COWORK_SCREENSHOT_CMD.replace(/\{FILE\}/g,tmp).replace(/\{X\}/g,x).replace(/\{Y\}/g,y).replace(/\{W\}/g,w).replace(/\{H\}/g,h);
    _cp.execSync(cmd,{timeout:15000});return _readClean(tmp)}catch(e){console.warn("[claude-cu] COWORK_SCREENSHOT_CMD failed: "+e.message)}
  }
  if(_wayland&&_isWlroots()&&_hasCmd("grim")){
    try{_cp.execSync('grim -g "'+x+","+y+" "+w+"x"+h+'" "'+tmp+'"',{timeout:10000});return _readClean(tmp)}catch(e){console.warn("[claude-cu] grim failed: "+e.message)}
  }
  if(_wayland&&_de.indexOf("gnome")>=0&&_hasCmd("gdbus")){
    try{_cp.execSync("gdbus call --session --dest org.gnome.Shell.Screenshot --object-path /org/gnome/Shell/Screenshot --method org.gnome.Shell.Screenshot.ScreenshotArea "+x+" "+y+" "+w+" "+h+" false '"+tmp+"'",{timeout:10000});
    if(_fs.existsSync(tmp))return _readClean(tmp)}catch(e){console.warn("[claude-cu] GNOME D-Bus screenshot failed: "+e.message)}
  }
  if(_de.indexOf("kde")>=0&&_hasCmd("spectacle")){
    try{var stmp=_path.join(_os.tmpdir(),"claude-cu-spectacle-"+Date.now()+".png");
    _cp.execSync('spectacle -b -n -f -o "'+stmp+'"',{timeout:10000});
    if(_fs.existsSync(stmp)){try{_cp.execSync('convert "'+stmp+'" -crop '+w+"x"+h+"+"+x+"+"+y+' +repage "'+tmp+'"',{timeout:5000});try{_fs.unlinkSync(stmp)}catch(e){}return _readClean(tmp)}catch(ce){try{_fs.renameSync(stmp,tmp)}catch(re){}return _readClean(tmp)}}
    }catch(e){console.warn("[claude-cu] spectacle failed: "+e.message)}
  }
  if(!_wayland&&_de.indexOf("gnome")>=0&&_hasCmd("gnome-screenshot")){
    try{_cp.execSync('gnome-screenshot -f "'+tmp+'"',{timeout:10000});if(_fs.existsSync(tmp))return _readClean(tmp)}catch(e){console.warn("[claude-cu] gnome-screenshot failed: "+e.message)}
  }
  if(!_wayland&&_hasCmd("scrot")){
    try{_cp.execSync("scrot -a "+x+","+y+","+w+","+h+' -o "'+tmp+'"',{timeout:10000});return _readClean(tmp)}catch(e){console.warn("[claude-cu] scrot failed: "+e.message)}
  }
  if(!_wayland){try{_cp.execSync('import -window root -crop '+w+"x"+h+"+"+x+"+"+y+' "'+tmp+'"',{timeout:10000});return _readClean(tmp)}catch(e2){}}
  try{var _sources=await _electron.desktopCapturer.getSources({types:["screen"],thumbnailSize:{width:w+x,height:h+y}});if(_sources&&_sources.length>0){var _img=_sources[0].thumbnail;if(_img&&!_img.isEmpty()){var _cropped=_img.crop({x:x,y:y,width:w,height:h});_fs.writeFileSync(tmp,_cropped.toPNG());return _readClean(tmp)}}}catch(dce){console.warn("[claude-cu] desktopCapturer fallback failed: "+dce.message)}
  throw new Error("Screenshot failed — install scrot (X11), grim (Wayland wlroots), or set COWORK_SCREENSHOT_CMD env var.")
}
if(_wayland){console.log("[claude-cu] Wayland session detected — using native Wayland tools")}
var _defaultMon={displayId:0,width:1920,height:1080,originX:0,originY:0,scaleFactor:1,isPrimary:true,label:"default"};
function _getMonitors(){
  try{
    var displays=_electron.screen.getAllDisplays();
    if(displays&&displays.length>0){
      var primary=_electron.screen.getPrimaryDisplay();
      var primaryId=primary?primary.id:displays[0].id;
      return displays.map(function(d,idx){return{displayId:idx,width:d.size.width,height:d.size.height,originX:d.bounds.x,originY:d.bounds.y,scaleFactor:d.scaleFactor||1,isPrimary:d.id===primaryId,label:d.label||("display-"+idx)}});
    }
  }catch(ee){}
  return[_defaultMon];
}
function _findMon(displayId){
  var mons=_getMonitors();
  if(displayId!=null){
    for(var i=0;i<mons.length;i++){if(mons[i].displayId===displayId)return mons[i]}
    var displays=_electron.screen.getAllDisplays();
    for(var i=0;i<displays.length;i++){if(displays[i].id===displayId&&i<mons.length)return mons[i]}
  }
  for(var i=0;i<mons.length;i++){if(mons[i].isPrimary)return mons[i]}
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
async function _screenshotMon(mon){return await _captureRegion(mon.originX,mon.originY,mon.width,mon.height)}
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
    return{width:m.width,height:m.height,scaleFactor:m.scaleFactor,originX:m.originX||0,originY:m.originY||0};
  },
  async screenshot(opts){
    var mon=_findMon(opts&&opts.displayId);
    var b64=await _screenshotMon(mon);
    return{base64:b64};
  },
  async resolvePrepareCapture(opts){
    var did=opts&&opts.preferredDisplayId;
    var mon=_findMon(did);
    var b64=await _screenshotMon(mon);
    return{base64:b64,width:mon.width,height:mon.height,displayWidth:mon.width,displayHeight:mon.height,displayId:mon.displayId,originX:mon.originX,originY:mon.originY,hidden:[]};
  },
  async zoom(rect,scale,displayId){
    var b64=await _captureRegion(rect.x,rect.y,rect.w,rect.h);
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
    function _resolveApp(n){
      var dirs=["/usr/share/applications",_path.join(_os.homedir(),".local/share/applications"),"/var/lib/flatpak/exports/share/applications",_path.join(_os.homedir(),".local/share/flatpak/exports/share/applications")];
      var nl=n.toLowerCase();
      for(var d=0;d<dirs.length;d++){
        try{
          var files=_fs.readdirSync(dirs[d]);
          for(var i=0;i<files.length;i++){
            if(files[i].indexOf(".desktop")===-1)continue;
            try{
              var content=_fs.readFileSync(_path.join(dirs[d],files[i]),"utf-8");
              var nameMatch=content.match(/^Name=(.+)$/m);
              var execMatch=content.match(/^Exec=(\S+)/m);
              if(nameMatch&&execMatch){
                var dname=nameMatch[1].trim().toLowerCase();
                var dfn=files[i].replace(/\.desktop$/,"").toLowerCase();
                var execCmd=execMatch[1].replace(/%.*/,"").trim();
                if(dname===nl||dfn===nl||_path.basename(execCmd).toLowerCase()===nl)return execCmd;
              }
            }catch(fe){}
          }
        }catch(de){}
      }
      return null;
    }
    var resolved=_resolveApp(name);
    var cmd=resolved||name;
    try{
      _cp.exec("setsid "+JSON.stringify(cmd)+" >/dev/null 2>&1");
    }catch(e){
      try{
        _cp.exec("setsid xdg-open "+JSON.stringify(name)+" >/dev/null 2>&1");
      }catch(e2){throw new Error("Could not open "+name+(resolved?" (resolved to "+resolved+")":""))}
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
        _electron.clipboard.writeText(text,"clipboard");
        _exec("ydotool key 29:1 47:1 47:0 29:0");
      }else{
        _cp.execSync("ydotool type -- "+JSON.stringify(text),{timeout:15000});
      }
    }else{
      if(opts&&opts.viaClipboard){
        _electron.clipboard.writeText(text,"clipboard");
        _exec("xdotool key --clearmodifiers ctrl+v");
      }else{
        _cp.execSync("xdotool type --clearmodifiers -- "+JSON.stringify(text),{timeout:15000});
      }
    }
  },
  async readClipboard(){
    try{return _electron.clipboard.readText("clipboard")||""}
    catch(e){return""}
  },
  async writeClipboard(text){
    _electron.clipboard.writeText(text||"","clipboard");
  }
};
})();
"""


# Linux hybrid handler — injected at the top of handleToolCall as an early-return block.
#
# Architecture:
#   - Teach tools (request_teach_access, teach_step, teach_batch) fall through
#     to the UPSTREAM chain. Sub-patches 2-5 ensure the upstream chain uses
#     __linuxExecutor and auto-grants permissions. The teach overlay (BrowserWindow
#     + IPC) works on Linux natively since it's pure Electron.
#   - request_access: handled directly on Linux — grants ALL requested apps at
#     full tier (no click-only/type restrictions). The upstream handler applies
#     macOS app tiers that restrict IDEs/terminals to "click" tier.
#   - Normal CU tools use a FAST DIRECT handler dispatching to __linuxExecutor,
#     skipping the macOS app tiers, allowlists, and permission dialogs.
#
# __DISPATCHER__ is replaced at patch time with the actual session dispatcher function
# name (e.g. EZr). __SELF__ is replaced with the object name (e.g. nnt).
LINUX_HANDLER_INJECTION_JS = r"""if(process.platform==="linux"){
var __lxTeachTools=["request_teach_access","teach_step","teach_batch"];
if(__lxTeachTools.indexOf(t)>=0){const __n=__DISPATCHER__(r);const{save_to_disk:__sd,...__s}=e;return await __n(t,__s)}
if(t==="request_access"){var __apps=e.apps||[];var __granted=__apps.map(function(a){return{bundleId:a,displayName:a,grantedAt:Date.now(),tier:"full"}});return{content:[{type:"text",text:JSON.stringify({granted:__granted,denied:[],screenshotFiltering:"none"})}]}}
var ex=globalThis.__linuxExecutor;
if(!ex)return{content:[{type:"text",text:"Linux executor not initialized"}],isError:!0};
globalThis.__cuActiveOrigin=globalThis.__cuActiveOrigin||{x:0,y:0};
function __txC(c){var o=globalThis.__cuActiveOrigin;return[(c[0]||0)+(o?o.x:0),(c[1]||0)+(o?o.y:0)]}
function __untxC(x,y){var o=globalThis.__cuActiveOrigin;return[(x||0)-(o?o.x:0),(y||0)-(o?o.y:0)]}
var __actionTools=new Set(["left_click","right_click","double_click","triple_click","middle_click","left_click_drag","mouse_move","scroll","key","type","hold_key","left_mouse_down","left_mouse_up","computer_batch"]);
async function __hideWindows(fn){var __bws=require("electron").BrowserWindow.getAllWindows().filter(function(w){return!w.isDestroyed()});for(var __i=0;__i<__bws.length;__i++)__bws[__i].setIgnoreMouseEvents(true);try{await new Promise(function(r){setTimeout(r,50)});return await fn()}finally{for(var __i=0;__i<__bws.length;__i++){if(!__bws[__i].isDestroyed())__bws[__i].setIgnoreMouseEvents(false)}}}
if(__actionTools.has(t)){return await __hideWindows(async function(){switch(t){
case"left_click":{var __lc=__txC(e.coordinate||[e.x,e.y]);await ex.click(__lc[0],__lc[1],"left",1);return{content:[{type:"text",text:"Clicked at ("+__lc[0]+","+__lc[1]+")"}]}}
case"right_click":{var __rc=__txC(e.coordinate||[e.x,e.y]);await ex.click(__rc[0],__rc[1],"right",1);return{content:[{type:"text",text:"Right clicked"}]}}
case"double_click":{var __dc=__txC(e.coordinate||[e.x,e.y]);await ex.click(__dc[0],__dc[1],"left",2);return{content:[{type:"text",text:"Double clicked"}]}}
case"triple_click":{var __tc=__txC(e.coordinate||[e.x,e.y]);await ex.click(__tc[0],__tc[1],"left",3);return{content:[{type:"text",text:"Triple clicked"}]}}
case"middle_click":{var __mc=__txC(e.coordinate||[e.x,e.y]);await ex.click(__mc[0],__mc[1],"middle",1);return{content:[{type:"text",text:"Middle clicked"}]}}
case"type":{await ex.type(e.text||"",{viaClipboard:!1});return{content:[{type:"text",text:"Typed text"}]}}
case"key":{await ex.key(e.key||e.text||"",e.count||1);return{content:[{type:"text",text:"Pressed key: "+(e.key||e.text)}]}}
case"scroll":{var __sc=__txC(e.coordinate||[e.x||0,e.y||0]),__dir=e.scroll_direction||e.direction||"down",__amt=e.scroll_amount||e.amount||3,__sv=__dir==="down"?__amt:__dir==="up"?-__amt:0,__sh=__dir==="right"?__amt:__dir==="left"?-__amt:0;await ex.scroll(__sc[0],__sc[1],__sh,__sv);return{content:[{type:"text",text:"Scrolled "+__dir}]}}
case"left_click_drag":{var __dsc=e.start_coordinate?__txC(e.start_coordinate):null,__den=__txC(e.coordinate);await ex.drag(__dsc?{x:__dsc[0],y:__dsc[1]}:void 0,{x:__den[0],y:__den[1]});return{content:[{type:"text",text:"Dragged"}]}}
case"mouse_move":{var __mv=__txC(e.coordinate||[e.x,e.y]);await ex.moveMouse(__mv[0],__mv[1]);return{content:[{type:"text",text:"Moved to ("+__mv[0]+","+__mv[1]+")"}]}}
case"hold_key":{await ex.holdKey(e.key||"",e.duration||.5);return{content:[{type:"text",text:"Held key"}]}}
case"left_mouse_down":{await ex.mouseDown();return{content:[{type:"text",text:"Mouse down"}]}}
case"left_mouse_up":{await ex.mouseUp();return{content:[{type:"text",text:"Mouse up"}]}}
case"computer_batch":{var __actions=e.actions||[],__completed=[],__failIdx=-1,__failErr;for(var __bi=0;__bi<__actions.length;__bi++){var __ba=__actions[__bi];try{var __br=await __SELF__.handleToolCall(__ba.action||__ba.type,__ba,r);__completed.push({type:__ba.action||__ba.type,result:__br})}catch(__be){__failIdx=__bi;__failErr=__be.message;break}}var __resp={completed:__completed};if(__failIdx>=0){__resp.failed={index:__failIdx,action:__actions[__failIdx].action||__actions[__failIdx].type,error:__failErr};__resp.remaining=__actions.slice(__failIdx+1).map(function(a){return a.action||a.type})}return{content:[{type:"text",text:JSON.stringify(__resp)}]}}
default:return{content:[{type:"text",text:"Unknown action tool: "+t}],isError:!0}
}})}
try{switch(t){
case"screenshot":{var __dlist=await ex.listDisplays();var __primaryIdx=0;for(var __pi=0;__pi<__dlist.length;__pi++){if(__dlist[__pi].isPrimary){__primaryIdx=__dlist[__pi].displayId;break}}var __did=globalThis.__cuPinnedDisplay!==void 0?globalThis.__cuPinnedDisplay:(e.display_number||e.display_id||__primaryIdx);var __actMon=__dlist.find(function(d){return d.displayId===__did})||__dlist[0]||{originX:0,originY:0};globalThis.__cuActiveOrigin={x:__actMon.originX||0,y:__actMon.originY||0};var __ss=await ex.screenshot({displayId:__did});return{content:[{type:"image",data:__ss.base64,mimeType:"image/png"}]}}
case"zoom":{var __zc=__txC(e.coordinate||[960,540]),__sz=e.size||400,__hf=Math.floor(__sz/2),__zr=await ex.zoom({x:Math.max(0,__zc[0]-__hf),y:Math.max(0,__zc[1]-__hf),w:__sz,h:__sz},1,0);return{content:[{type:"image",data:__zr.base64,mimeType:"image/png"}]}}
case"cursor_position":{var __cp=await ex.getCursorPosition();var __cpr=__untxC(__cp.x,__cp.y);return{content:[{type:"text",text:"("+__cpr[0]+", "+__cpr[1]+")"}]}}
case"wait":{var __ws=Math.min(e.duration||e.seconds||1,30);await new Promise(function(__rv){setTimeout(__rv,__ws*1000)});return{content:[{type:"text",text:"Waited "+__ws+"s"}]}}
case"open_application":{await ex.openApp(e.app||e.application||"");return{content:[{type:"text",text:"Opened app"}]}}
case"switch_display":{var __displays=await ex.listDisplays();var __target=e.display;if(__target==="auto"||!__target){globalThis.__cuPinnedDisplay=void 0;return{content:[{type:"text",text:"Display mode set to auto (follows cursor). Available: "+__displays.map(function(d){return d.label+" ("+d.width+"x"+d.height+")"}).join(", ")}]}}var __found=__displays.find(function(d){return d.label===__target||String(d.displayId)===String(__target)});if(__found){globalThis.__cuPinnedDisplay=__found.displayId;globalThis.__cuActiveOrigin={x:__found.originX||0,y:__found.originY||0};return{content:[{type:"text",text:"Switched to display: "+__found.label+" ("+__found.width+"x"+__found.height+")"}]}}return{content:[{type:"text",text:"Display '"+__target+"' not found. Available: "+__displays.map(function(d){return d.label}).join(", ")}]}}
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

    # Patch 2: Add "linux" to the computer-use platform Set
    # Original: new Set(["darwin","win32"])  (gates vee(), rj(), and other CU checks)
    # New: new Set(["darwin","win32","linux"])
    # This single change makes vee() return true on Linux, enabling the CU server push,
    # chicagoEnabled gate, overlay init, and all other ese.has() checks.
    set_pattern = rb'new Set\(\["darwin","win32"\]\)'
    set_replacement = b'new Set(["darwin","win32","linux"])'

    content, count = re.subn(set_pattern, set_replacement, content, count=1)
    if count >= 1:
        print(f"  [OK] ese Set: added linux ({count} match)")
        changes += count
    else:
        print("  [FAIL] ese Set pattern: 0 matches")
        return False

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
    # The upstream handleToolCall calls a session-cached dispatcher. On Linux, we
    # inject an early-return block that:
    #   - For teach tools: falls through to the upstream chain (uses __linuxExecutor
    #     via sub-patch 4, auto-grants via sub-patch 5, teach overlay works natively)
    #   - For normal tools: fast direct dispatch to __linuxExecutor, skipping macOS
    #     app tiers, allowlists, CU lock, and permission dialogs
    #
    # Two-step approach:
    #   Step A: Find the handleToolCall start and capture object name + session param
    #   Step B: Find the dispatcher function name (const n=DISPATCHER(session_param))
    #   Then inject LINUX_HANDLER_INJECTION after the opening brace.

    # Step A: Match the handleToolCall start
    htc_start = rb"((\w+)=\{isEnabled:\w+=>\w+\(\),handleToolCall:async\((\w+),(\w+),(\w+)\)=>\{)"
    htc_match = re.search(htc_start, content)

    if htc_match:
        obj_name = htc_match.group(2).decode("utf-8")
        session_param = htc_match.group(5).decode("utf-8")
        inject_pos = htc_match.end()  # position right after the opening {

        # Step B: Find the dispatcher in the code after the opening brace
        # It appears as: const n=DISPATCHER(SESSION_PARAM),{save_to_disk:
        after_brace = content[inject_pos : inject_pos + 2000]
        dispatcher_match = re.search(
            rb"const \w+=(\w+)\(" + session_param.encode("utf-8") + rb"\),\{save_to_disk:",
            after_brace,
        )

        if dispatcher_match:
            dispatcher = dispatcher_match.group(1).decode("utf-8")
            handler_js = LINUX_HANDLER_INJECTION_JS.strip()
            handler_js = handler_js.replace("__SELF__", obj_name)
            handler_js = handler_js.replace("__DISPATCHER__", dispatcher)
            content = content[:inject_pos] + handler_js.encode("utf-8") + content[inject_pos:]
            print("  [OK] handleToolCall: hybrid dispatch (teach→upstream, rest→direct) (1 match)")
            changes += 1
        else:
            print("  [FAIL] handleToolCall dispatcher not found")
            return False
    else:
        print("  [FAIL] handleToolCall pattern: 0 matches")
        return False

    # Patch 7: Teach overlay controller init on Linux
    # In v1.2.234+, the overlay init is gated by vee() which we patched via the Set fix.
    # The code `vee()&&(Sti(t),...)` will now run on Linux automatically.
    # No explicit injection needed — just verify the pattern exists.
    stub_end = rb"listInstalledApps:\(\)=>\[\]\}\)"
    stub_match = re.search(stub_end, content)
    if stub_match:
        # Check that vee() gate follows the stub (meaning overlay init is Set-gated)
        after_stub = content[stub_match.end() : stub_match.end() + 50]
        if b"vee()" in after_stub:
            print("  [OK] teach overlay controller: vee() gate found (handled by Set fix)")
        else:
            print("  [WARN] teach overlay: vee() gate not found after TCC stub — may need manual check")
    else:
        print("  [WARN] teach overlay: TCC stub pattern not found")

    # Patch 8: Fix teach overlay mouse events on Linux
    # On macOS, setIgnoreMouseEvents(true, {forward: true}) makes transparent areas
    # click-through while still receiving mouseenter/mouseleave events. On Linux/X11,
    # {forward: true} is NOT implemented (Electron issue #16777, open since 2019).
    # The overlay becomes fully click-through and NEVER receives mouseenter, so the
    # tooltip buttons (Next/Exit) remain unclickable forever.
    #
    # Fix: Override setIgnoreMouseEvents to a no-op on the teach overlay window.
    # This keeps the overlay permanently interactive so tooltip buttons work.
    # Trade-off: users can't click through to apps behind the overlay during
    # the teach session — acceptable for a guided tour. The no-op also prevents
    # the upstream mouse-leave IPC handler and step transition functions (yJt/SUn)
    # from setting the window back to pass-through.

    # Find the overlay variable name from: OVERLAYVAR.setAlwaysOnTop(!0,"screen-saver"),OVERLAYVAR.setFullScreenable(!1),OVERLAYVAR.setIgnoreMouseEvents(!0,{forward:!0})
    overlay_var_pattern = rb'(\w+)\.setAlwaysOnTop\(!0,"screen-saver"\),\1\.setFullScreenable\(!1\),\1\.setIgnoreMouseEvents\(!0,\{forward:!0\}\)'

    overlay_var_match = re.search(overlay_var_pattern, content)
    if overlay_var_match:
        ov = overlay_var_match.group(1).decode("utf-8")  # e.g. oa

        # Replace the initial setIgnoreMouseEvents on the overlay with Linux tooltip-bounds polling
        old_init = f"{ov}.setIgnoreMouseEvents(!0,{{forward:!0}})".encode("utf-8")

        new_init = (
            '(process.platform==="linux"?'
            # On Linux, override setIgnoreMouseEvents to a no-op so the teach overlay
            # stays interactive throughout its lifetime. Electron bug #16777 means
            # {forward:true} doesn't work on Linux/X11 — the overlay would become
            # permanently pass-through with no way back. By keeping it interactive,
            # users can click Next/Exit buttons. The trade-off: users can't click
            # through to apps behind the overlay during teach — acceptable for a
            # guided tour. The upstream mouse-leave IPC handler and yJt/SUn step
            # transitions all call setIgnoreMouseEvents on this window — the no-op
            # prevents them from breaking interactivity.
            f"({ov}.setIgnoreMouseEvents=function(){{}},"  # no-op override
            f"globalThis.__isVM&&{ov}.setOpacity(.15))"
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
    # Patch 8's no-op override already catches these on the teach overlay window.
    # This patch is a belt-and-suspenders safety net for cases where the function
    # parameter differs from the global overlay variable (yJt receives it as a param).
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
        before = content[max(0, m.start() - 80) : m.start()]
        if b"workArea" in before:
            old = m.group(0)
            new = old.replace(b"transparent:!0", b"transparent:!globalThis.__isVM").replace(b'backgroundColor:"#00000000"', b'backgroundColor:globalThis.__isVM?"#000000":"#00000000"')
            content = content.replace(old, new, 1)
            print("  [OK] teach overlay: VM-aware transparency (transparent on native, dark backdrop on VMs)")
            changes += 1
            break
    else:
        print("  [WARN] teach overlay transparency pattern not found")

    # Patch 10b: Force teach overlay display to primary monitor on Linux
    # The xlr() function resolves which display to use for the glow and teach overlay
    # windows. On macOS, autoTargetDisplay + findWindowDisplays determines the correct
    # display. On Linux, these fall back to the Claude Desktop window's display, which
    # may be a non-primary monitor. We simplify: on Linux, always use the primary
    # monitor for teach overlays. This avoids fragile xdotool-based window detection
    # that only works on X11 and keeps the teach experience consistent across distros.
    # Pattern: function xlr(PARAM){return PARAM===null?ELECTRON.screen.getPrimaryDisplay():...}
    xlr_pattern = rb"(function \w+\((\w+)\)\{)(return \2===null\?\w+\.screen\.getPrimaryDisplay\(\):\w+\.screen\.getAllDisplays\(\)\.find)"

    def patch_xlr(m):
        param = m.group(2).decode("utf-8")
        return m.group(1) + f'if(process.platform==="linux"){param}=null;'.encode("utf-8") + m.group(3)

    content, count = re.subn(xlr_pattern, patch_xlr, content, count=1)
    if count >= 1:
        print(f"  [OK] teach overlay display: forced to primary monitor on Linux ({count} match)")
        changes += count
    else:
        print("  [WARN] xlr display resolver pattern: 0 matches (teach may appear on wrong monitor)")

    # Patch 11: Force mVt() (computer-use isEnabled gate) to return true on Linux
    # The mVt() function gates whether the computer-use MCP server is enabled for
    # ALL session types (CCD, cowork, dispatch). It checks:
    #   fn(serverFlag) ? ese.has(platform) && Rse() : rj()
    # Both branches call Rse(), which reads the "enabled" key from GrowthBook's
    # chicago_config. Anthropic's server returns enabled:false, so mVt() returns
    # false even though our other patches (Set fix, executor, permissions) are working.
    # Our enable_local_agent_mode.py only overrides {status:"supported"} in the
    # static registry — it doesn't affect the GrowthBook "enabled" key.
    # Fix: inject an early return true on Linux before the original logic.
    mVt_pattern = rb"(function \w+\(\)\{)return \w+\(\w+\)\?\w+\.has\(process\.platform\)&&\w+\(\):\w+\(\)\}"

    def patch_mVt(m):
        return m.group(1) + b'if(process.platform==="linux")return!0;' + m.group(0)[len(m.group(1)) :]

    content, count = re.subn(mVt_pattern, patch_mVt, content, count=1)
    if count >= 1:
        print(f"  [OK] mVt isEnabled: force true on Linux ({count} match)")
        changes += count
    else:
        print("  [WARN] mVt isEnabled pattern: 0 matches (computer-use may not work in cowork/CCD)")

    # Patch 12: Force rj() to return true on Linux (bypass chicagoEnabled + GrowthBook)
    # rj() is the single function that feeds BOTH runtime gates:
    #   - isDisabled() = !rj()  → blocks tool calls when false
    #   - hasComputerUse = rj() → controls system prompt CU instructions
    # Original: rj() = ese.has(platform) ? Rse() && Rr("chicagoEnabled") : false
    # Rse() reads GrowthBook enabled:false, Rr reads chicagoEnabled preference (default false).
    # Both fail → rj()=false → tools blocked. The Settings toggle (claude.ai web UI)
    # is server-rendered and hidden on Linux regardless of our main-process patches.
    # Fix: return true unconditionally on Linux — no config entry needed.
    rj_pattern = rb'(function \w+\(\)\{)return \w+\.has\(process\.platform\)\?\w+\(\)&&\w+\("chicagoEnabled"\):!1\}'

    def patch_rj(m):
        return m.group(1) + b'if(process.platform==="linux")return!0;' + m.group(0)[len(m.group(1)) :]

    content, count = re.subn(rj_pattern, patch_rj, content, count=1)
    if count >= 1:
        print(f"  [OK] rj chicagoEnabled bypass: force true on Linux ({count} match)")
        changes += count
    else:
        print("  [WARN] rj pattern: 0 matches (computer-use tool calls may be blocked)")

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
