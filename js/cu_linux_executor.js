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
var _portalTokenPath=_path.join(_os.homedir(),".config","Claude","pipewire-restore-token");
var _portalPyCode="import sys,os,signal,subprocess\nTOKEN_FILE=os.path.expanduser('~/.config/Claude/pipewire-restore-token')\nTIMEOUT_SECS=10\ndef main():\n    if len(sys.argv)<2:\n        print('Usage: gnome-portal-screenshot.py <output.png> [x y w h]',file=sys.stderr);return 1\n    output_path=sys.argv[1]\n    crop=tuple(int(x) for x in sys.argv[2:6]) if len(sys.argv)>=6 else None\n    try:\n        import gi\n        gi.require_version('Gst','1.0')\n        from gi.repository import GLib,Gio,Gst\n    except (ImportError,ValueError) as e:\n        print(f'[portal-screenshot] missing deps: {e}',file=sys.stderr);return 2\n    Gst.init(None)\n    restore_token=''\n    try:\n        with open(TOKEN_FILE) as f: restore_token=f.read().strip()\n    except FileNotFoundError: pass\n    bus=Gio.bus_get_sync(Gio.BusType.SESSION)\n    loop=GLib.MainLoop()\n    state={'node_id':None,'new_token':'','session':'','error':None,'done':False}\n    unique_name=bus.get_unique_name().replace('.','_').replace(':','')\n    counter=[0]\n    def next_token():\n        counter[0]+=1;return f'claude_{os.getpid()}_{counter[0]}'\n    def subscribe_response(handle_path,callback):\n        sub_id=[None]\n        def on_signal(_conn,_sender,_path,_iface,_sig,params):\n            bus.signal_unsubscribe(sub_id[0]);resp,results=params.unpack();callback(resp,results)\n        sub_id[0]=bus.signal_subscribe('org.freedesktop.portal.Desktop','org.freedesktop.portal.Request','Response',handle_path,None,0,on_signal);return sub_id[0]\n    def portal_call(method,args_variant):\n        return bus.call_sync('org.freedesktop.portal.Desktop','/org/freedesktop/portal/desktop','org.freedesktop.portal.ScreenCast',method,args_variant,None,0,TIMEOUT_SECS*1000,None)\n    def fail(msg):\n        state['error']=msg\n        if loop.is_running(): loop.quit()\n    def do_start():\n        ht=next_token();hp=f'/org/freedesktop/portal/desktop/request/{unique_name}/{ht}'\n        def on_start(resp,results):\n            if resp!=0: fail(f'Start rejected ({resp})');return\n            streams=results.get('streams',None);new_tok=results.get('restore_token','')\n            if new_tok: state['new_token']=new_tok\n            if streams:\n                sl=streams.unpack() if hasattr(streams,'unpack') else streams\n                if sl: state['node_id']=sl[0][0] if isinstance(sl[0],tuple) else sl[0]\n            state['done']=True;loop.quit()\n        subscribe_response(hp,on_start)\n        portal_call('Start',GLib.Variant('(osa{sv})',(state['session'],'',{'handle_token':GLib.Variant('s',ht)})))\n    def do_select():\n        ht=next_token();hp=f'/org/freedesktop/portal/desktop/request/{unique_name}/{ht}'\n        def on_select(resp,_results):\n            if resp!=0: fail(f'SelectSources rejected ({resp})');return\n            do_start()\n        subscribe_response(hp,on_select)\n        opts={'handle_token':GLib.Variant('s',ht),'types':GLib.Variant('u',1),'multiple':GLib.Variant('b',False),'persist_mode':GLib.Variant('u',2)}\n        if restore_token: opts['restore_token']=GLib.Variant('s',restore_token)\n        portal_call('SelectSources',GLib.Variant('(oa{sv})',(state['session'],opts)))\n    def do_create():\n        ht=next_token();st=f'claude_sess_{os.getpid()}'\n        hp=f'/org/freedesktop/portal/desktop/request/{unique_name}/{ht}'\n        def on_create(resp,results):\n            if resp!=0: fail(f'CreateSession rejected ({resp})');return\n            sh=results.get('session_handle','')\n            if not sh: fail('No session handle');return\n            state['session']=sh;do_select()\n        subscribe_response(hp,on_create)\n        portal_call('CreateSession',GLib.Variant('(a{sv})',({'handle_token':GLib.Variant('s',ht),'session_handle_token':GLib.Variant('s',st)},)))\n    GLib.timeout_add_seconds(TIMEOUT_SECS,lambda:(fail('timeout') if not state['done'] else None,False)[-1])\n    try: do_create();loop.run()\n    except Exception as e: fail(str(e))\n    if state['error']:\n        print(f'[portal-screenshot] {state[\"error\"]}',file=sys.stderr);return 1\n    if not state['node_id']:\n        print('[portal-screenshot] no PipeWire node',file=sys.stderr);return 1\n    if state['new_token']:\n        try:\n            os.makedirs(os.path.dirname(TOKEN_FILE),exist_ok=True)\n            with open(TOKEN_FILE,'w') as f: f.write(state['new_token'])\n        except OSError: pass\n    node_id=state['node_id']\n    try:\n        pipeline=Gst.parse_launch(f'pipewiresrc path={node_id} num-buffers=1 ! videoconvert ! pngenc ! filesink location=\"{output_path}\"')\n        pipeline.set_state(Gst.State.PLAYING)\n        gst_bus=pipeline.get_bus()\n        msg=gst_bus.timed_pop_filtered(5*Gst.SECOND,Gst.MessageType.EOS|Gst.MessageType.ERROR)\n        if msg and msg.type==Gst.MessageType.ERROR:\n            err,_=msg.parse_error();print(f'[portal-screenshot] GStreamer: {err.message}',file=sys.stderr)\n            pipeline.set_state(Gst.State.NULL);return 1\n        pipeline.set_state(Gst.State.NULL)\n    except Exception as e:\n        print(f'[portal-screenshot] GStreamer failed: {e}',file=sys.stderr);return 1\n    if not os.path.exists(output_path): return 1\n    if crop:\n        cx,cy,cw,ch=crop\n        try:\n            from gi.repository import GdkPixbuf\n            pb=GdkPixbuf.Pixbuf.new_from_file(output_path)\n            pw,ph=pb.get_width(),pb.get_height()\n            cx=min(cx,pw-1);cy=min(cy,ph-1);cw=min(cw,pw-cx);ch=min(ch,ph-cy)\n            cr=GdkPixbuf.Pixbuf.new(GdkPixbuf.Colorspace.RGB,pb.get_has_alpha(),8,cw,ch)\n            pb.copy_area(cx,cy,cw,ch,cr,0,0);cr.savev(output_path,'png',[],[])\n        except ImportError:\n            try: subprocess.run(['convert',output_path,'-crop',f'{cw}x{ch}+{cx}+{cy}','+repage',output_path],timeout=5,check=True,capture_output=True)\n            except Exception: pass\n    if state['session']:\n        try: bus.call_sync('org.freedesktop.portal.Desktop',state['session'],'org.freedesktop.portal.Session','Close',None,None,0,1000,None)\n        except Exception: pass\n    return 0\nif __name__=='__main__':\n    signal.signal(signal.SIGALRM,lambda *_:sys.exit(1));signal.alarm(TIMEOUT_SECS+5);sys.exit(main())";
function _hasPortalDeps(){return _hasCmd("python3")&&_hasCmd("gst-launch-1.0")}
function _hasPortalToken(){try{_fs.accessSync(_portalTokenPath);return true}catch(e){return false}}
async function _portalScreenshot(tmp,x,y,w,h){
  return new Promise(function(resolve){var ch=_cp.spawn("python3",["-",tmp,String(x),String(y),String(w),String(h)],{stdio:["pipe","pipe","pipe"]});ch.stdin.write(_portalPyCode);ch.stdin.end();var se="";ch.stderr.on("data",function(d){se+=d.toString()});var timer=setTimeout(function(){ch.kill("SIGKILL");resolve({status:1,stderr:"timeout"})},15000);ch.on("close",function(code){clearTimeout(timer);resolve({status:code,stderr:se})});ch.on("error",function(e){clearTimeout(timer);resolve({status:1,stderr:e.message})})});
}
function _findMonByPoint(px,py){
  var mons=_getMonitors();
  for(var i=0;i<mons.length;i++){var m=mons[i];if(px>=m.originX&&px<m.originX+m.width&&py>=m.originY&&py<m.originY+m.height)return m}
  for(var i=0;i<mons.length;i++){if(mons[i].isPrimary)return mons[i]}
  return mons[0];
}
async function _captureRegion(x,y,w,h,sf){
  if(!sf){var _m=_findMonByPoint(x,y);sf=_m?_m.scaleFactor:1}
  if(sf&&sf!==1){x=Math.round(x*sf);y=Math.round(y*sf);w=Math.round(w*sf);h=Math.round(h*sf)}
  var tmp=_path.join(_os.tmpdir(),"claude-cu-"+Date.now()+"-"+Math.random().toString(36).slice(2)+".png");
  var _de=_desktopId();
  if(process.env.COWORK_SCREENSHOT_CMD){
    try{var cmd=process.env.COWORK_SCREENSHOT_CMD.replace(/\{FILE\}/g,tmp).replace(/\{X\}/g,x).replace(/\{Y\}/g,y).replace(/\{W\}/g,w).replace(/\{H\}/g,h);
    _cp.execSync(cmd,{timeout:15000});console.log("[claude-cu] screenshot: captured via COWORK_SCREENSHOT_CMD");return _readClean(tmp)}catch(e){console.warn("[claude-cu] COWORK_SCREENSHOT_CMD failed: "+e.message)}
  }
  if(_wayland&&_isWlroots()&&_hasCmd("grim")){
    try{_cp.execSync('grim -g "'+x+","+y+" "+w+"x"+h+'" "'+tmp+'"',{timeout:10000});console.log("[claude-cu] screenshot: captured via grim (wlroots)");return _readClean(tmp)}catch(e){console.warn("[claude-cu] grim failed: "+e.message)}
  }
  if(_wayland&&_de.indexOf("gnome")>=0&&_hasPortalToken()&&_hasPortalDeps()){
    try{var ret=await _portalScreenshot(tmp,x,y,w,h);
    if(ret.status===0&&_fs.existsSync(tmp)){console.log("[claude-cu] screenshot: captured via portal+pipewire (GNOME, restore token)");return _readClean(tmp)}
    if(ret.status===2){console.warn("[claude-cu] portal screenshot: missing python deps (python3-gi, gstreamer)")}
    else{console.warn("[claude-cu] portal screenshot failed (exit="+ret.status+"): "+(ret.stderr?ret.stderr.trim():""))}}catch(e){console.warn("[claude-cu] portal screenshot error: "+e.message)}
  }
  if(_wayland&&_de.indexOf("gnome")>=0&&_hasCmd("gnome-screenshot")){
    try{var _gstmp=_path.join(_os.tmpdir(),"claude-cu-gnome-"+Date.now()+".png");
    _cp.execSync('gnome-screenshot -f "'+_gstmp+'"',{timeout:10000});
    if(_fs.existsSync(_gstmp)){if(_hasCmd("convert")){try{_cp.execSync('convert "'+_gstmp+'" -crop '+w+"x"+h+"+"+x+"+"+y+' +repage "'+tmp+'"',{timeout:5000});try{_fs.unlinkSync(_gstmp)}catch(e){}console.log("[claude-cu] screenshot: captured via gnome-screenshot+convert (Wayland GNOME)");return _readClean(tmp)}catch(ce){try{_fs.renameSync(_gstmp,tmp)}catch(re){}console.log("[claude-cu] screenshot: captured via gnome-screenshot (Wayland GNOME, uncropped)");return _readClean(tmp)}}else{try{_fs.renameSync(_gstmp,tmp)}catch(re){}console.log("[claude-cu] screenshot: captured via gnome-screenshot (Wayland GNOME, uncropped)");return _readClean(tmp)}}
    }catch(e){console.warn("[claude-cu] gnome-screenshot (Wayland) failed: "+e.message)}
  }
  if(_wayland&&_de.indexOf("gnome")>=0&&_hasCmd("gdbus")){
    try{_cp.execSync("gdbus call --session --dest org.gnome.Shell.Screenshot --object-path /org/gnome/Shell/Screenshot --method org.gnome.Shell.Screenshot.ScreenshotArea "+x+" "+y+" "+w+" "+h+" false '"+tmp+"'",{timeout:10000});
    if(_fs.existsSync(tmp)){console.log("[claude-cu] screenshot: captured via gdbus (GNOME Shell Screenshot D-Bus)");return _readClean(tmp)}}catch(e){console.warn("[claude-cu] GNOME D-Bus screenshot failed: "+e.message)}
  }
  if(_wayland&&_de.indexOf("gnome")>=0&&!_hasPortalToken()&&_hasPortalDeps()){
    try{var ret=await _portalScreenshot(tmp,x,y,w,h);
    if(ret.status===0&&_fs.existsSync(tmp)){console.log("[claude-cu] screenshot: captured via portal+pipewire (GNOME, first-run)");return _readClean(tmp)}
    if(ret.status===2){console.warn("[claude-cu] portal screenshot: missing python deps (python3-gi, gstreamer)")}
    else{console.warn("[claude-cu] portal screenshot failed (exit="+ret.status+"): "+(ret.stderr?ret.stderr.trim():""))}}catch(e){console.warn("[claude-cu] portal screenshot error: "+e.message)}
  }
  if(_de.indexOf("kde")>=0&&_hasCmd("spectacle")){
    try{var stmp=_path.join(_os.tmpdir(),"claude-cu-spectacle-"+Date.now()+".png");
    _cp.execSync('spectacle -b -n -f -o "'+stmp+'"',{timeout:10000});
    if(_fs.existsSync(stmp)){try{_cp.execSync('convert "'+stmp+'" -crop '+w+"x"+h+"+"+x+"+"+y+' +repage "'+tmp+'"',{timeout:5000});try{_fs.unlinkSync(stmp)}catch(e){}console.log("[claude-cu] screenshot: captured via spectacle+convert (KDE)");return _readClean(tmp)}catch(ce){try{_fs.renameSync(stmp,tmp)}catch(re){}console.log("[claude-cu] screenshot: captured via spectacle (KDE, uncropped)");return _readClean(tmp)}}
    }catch(e){console.warn("[claude-cu] spectacle failed: "+e.message)}
  }
  if(!_wayland&&_de.indexOf("gnome")>=0&&_hasCmd("gnome-screenshot")){
    try{_cp.execSync('gnome-screenshot -f "'+tmp+'"',{timeout:10000});if(_fs.existsSync(tmp)){console.log("[claude-cu] screenshot: captured via gnome-screenshot (X11)");return _readClean(tmp)}}catch(e){console.warn("[claude-cu] gnome-screenshot failed: "+e.message)}
  }
  if(!_wayland&&_hasCmd("scrot")){
    try{_cp.execSync("scrot -a "+x+","+y+","+w+","+h+' -o "'+tmp+'"',{timeout:10000});console.log("[claude-cu] screenshot: captured via scrot (X11)");return _readClean(tmp)}catch(e){console.warn("[claude-cu] scrot failed: "+e.message)}
  }
  if(!_wayland){try{_cp.execSync('import -window root -crop '+w+"x"+h+"+"+x+"+"+y+' "'+tmp+'"',{timeout:10000});console.log("[claude-cu] screenshot: captured via import (ImageMagick, X11)");return _readClean(tmp)}catch(e2){console.warn("[claude-cu] import (ImageMagick) failed: "+(e2.message||e2))}}
  try{var _sources=await _electron.desktopCapturer.getSources({types:["screen"],thumbnailSize:{width:w+x,height:h+y}});if(_sources&&_sources.length>0){var _img=_sources[0].thumbnail;if(_img&&!_img.isEmpty()){var _cropped=_img.crop({x:x,y:y,width:w,height:h});_fs.writeFileSync(tmp,_cropped.toPNG());console.log("[claude-cu] screenshot: captured via desktopCapturer (Electron fallback)");return _readClean(tmp)}}}catch(dce){console.warn("[claude-cu] desktopCapturer fallback failed: "+dce.message)}
  throw new Error("Screenshot failed — install scrot (X11), grim (Wayland wlroots), or set COWORK_SCREENSHOT_CMD env var.")
}
if(_wayland){console.log("[claude-cu] Wayland session detected — using native Wayland tools")}
(function(){
  var _de=_desktopId();var _wlr=_wayland?_isWlroots():false;
  var _isGnome=_de.indexOf("gnome")>=0;var _isKde=_de.indexOf("kde")>=0;
  var _isHypr=!!process.env.HYPRLAND_INSTANCE_SIGNATURE;var _isSway=!!process.env.SWAYSOCK;
  var _relevant=[];
  if(_wayland&&_wlr)_relevant.push("grim");
  if(_wayland&&_isGnome){_relevant.push("gst-launch-1.0");_relevant.push("gnome-screenshot");_relevant.push("gdbus")}
  if(_isKde){_relevant.push("spectacle");_relevant.push("convert")}
  if(!_wayland&&_isGnome)_relevant.push("gnome-screenshot");
  if(!_wayland)_relevant.push("scrot","import");
  if(_wayland)_relevant.push("ydotool");
  _relevant.push("xdotool");
  if(!_wayland)_relevant.push("wmctrl");
  if(_isHypr)_relevant.push("hyprctl");
  if(_isSway){_relevant.push("swaymsg");_relevant.push("jq")}
  _relevant.push("xdg-open");
  var avail=_relevant.filter(function(t){return _hasCmd(t)});
  var missing=_relevant.filter(function(t){return !_hasCmd(t)});
  console.log("[claude-cu] diagnostics: session="+(_wayland?"wayland":"x11")+" de="+(_de||"unknown")+" wlroots="+_wlr+" vm="+!!globalThis.__isVM);
  try{var _diagMons=_getMonitors();console.log("[claude-cu] diagnostics: displays=["+_diagMons.map(function(m){return m.label+"("+m.width+"x"+m.height+"+"+m.originX+"+"+m.originY+" sf="+m.scaleFactor+(m.isPrimary?" primary":"")+")"}).join(", ")+"]")}catch(me){}
  console.log("[claude-cu] diagnostics: available=["+avail.join(", ")+"]");
  if(missing.length)console.warn("[claude-cu] diagnostics: missing=["+missing.join(", ")+"] (install for full functionality)");
  if(_wayland){
    var ydOk=_checkYdotool();
    console.log("[claude-cu] diagnostics: input-backend="+(ydOk?"ydotool":"xdotool (XWayland fallback)"));
  }else{
    console.log("[claude-cu] diagnostics: input-backend=xdotool");
  }
  var _hasToken=_hasPortalToken();var _hasPDeps=_hasPortalDeps();
  var order=[];
  if(process.env.COWORK_SCREENSHOT_CMD)order.push("COWORK_SCREENSHOT_CMD");
  if(_wayland&&_wlr&&_hasCmd("grim"))order.push("grim");
  if(_wayland&&_isGnome&&_hasToken&&_hasPDeps)order.push("portal+pipewire");
  if(_wayland&&_isGnome&&_hasCmd("gnome-screenshot"))order.push("gnome-screenshot");
  if(_wayland&&_isGnome&&_hasCmd("gdbus"))order.push("gdbus");
  if(_wayland&&_isGnome&&!_hasToken&&_hasPDeps)order.push("portal+pipewire");
  if(_isKde&&_hasCmd("spectacle"))order.push("spectacle");
  if(!_wayland&&_isGnome&&_hasCmd("gnome-screenshot"))order.push("gnome-screenshot");
  if(!_wayland&&_hasCmd("scrot"))order.push("scrot");
  if(!_wayland&&_hasCmd("import"))order.push("import");
  order.push("desktopCapturer");
  console.log("[claude-cu] diagnostics: screenshot-cascade=["+order.join(" > ")+"]");
  if(_wayland&&_isGnome){console.log("[claude-cu] diagnostics: pipewire-restore-token="+(_hasToken?"found (portal screenshots will skip permission dialog)":"none (first portal screenshot will show permission dialog)"))}
})();
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
var _inputLogDone={mouse:false,click:false,key:false,type:false,scroll:false,drag:false,window:false,app:false};
function _logFirstUse(op,backend){if(!_inputLogDone[op]){_inputLogDone[op]=true;console.log("[claude-cu] "+op+": using "+backend)}}
function _moveMouse(x,y){
  if(_wayland&&_checkYdotool()){
    try{_logFirstUse("mouse","ydotool");_exec("ydotool mousemove --absolute 0 0");_cp.execSync("sleep 0.05");_exec("ydotool mousemove "+Math.round(x)+" "+Math.round(y));return}catch(e){console.warn("[claude-cu] ydotool mousemove failed, falling back to xdotool: "+e.message)}
  }else{
    if(_wayland&&!_checkYdotool())console.warn("[claude-cu] ydotool not available on Wayland, falling back to xdotool via XWayland");
  }
  _logFirstUse("mouse","xdotool");
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
async function _screenshotMon(mon){return await _captureRegion(mon.originX,mon.originY,mon.width,mon.height,mon.scaleFactor||1)}
function _getActiveWindowWayland(){
  try{
    if(process.env.HYPRLAND_INSTANCE_SIGNATURE&&_hasCmd("hyprctl")){
      var out=_exec("hyprctl activewindow -j 2>/dev/null");
      var w=JSON.parse(out);
      if(w&&(w.class||w.title)){_logFirstUse("window","hyprctl");return{bundleId:w.class||w.title,displayName:w.title||w.class}}
    }
  }catch(he){}
  try{
    if(process.env.SWAYSOCK&&_hasCmd("swaymsg")&&_hasCmd("jq")){
      var out=_exec("swaymsg -t get_tree 2>/dev/null|jq -r '.. | select(.focused? == true) | {app_id, name}'");
      var w=JSON.parse(out);
      if(w&&(w.app_id||w.name)){_logFirstUse("window","swaymsg+jq");return{bundleId:w.app_id||w.name,displayName:w.name||w.app_id}}
    }
  }catch(se){}
  return null;
}
function _listRunningAppsWayland(){
  var apps=[],seen={};
  try{
    if(process.env.HYPRLAND_INSTANCE_SIGNATURE&&_hasCmd("hyprctl")){
      console.log("[claude-cu] listRunningApps: using hyprctl clients");
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
      console.log("[claude-cu] listRunningApps: using swaymsg+jq");
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
    var mon=displayId!=null?_findMon(displayId):_findMonByPoint(rect.x,rect.y);
    var sf=mon?mon.scaleFactor:1;
    console.log("[claude-cu] zoom: rect="+JSON.stringify(rect)+" scale="+scale+" displayId="+displayId+" mon="+((mon&&mon.label)||"?")+" sf="+sf);
    var b64=await _captureRegion(rect.x,rect.y,rect.w,rect.h,sf);
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
      console.log("[claude-cu] listRunningApps: using wmctrl/xdotool (X11)");
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
      _logFirstUse("window","xdotool");
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
      console.log("[claude-cu] openApp: launching via setsid "+cmd);
      _cp.exec("setsid "+JSON.stringify(cmd)+" >/dev/null 2>&1");
    }catch(e){
      try{
        console.log("[claude-cu] openApp: fallback to xdg-open "+name);
        _cp.exec("setsid xdg-open "+JSON.stringify(name)+" >/dev/null 2>&1");
      }catch(e2){throw new Error("Could not open "+name+(resolved?" (resolved to "+resolved+")":""))}
    }
  },
  async moveMouse(x,y){_moveMouse(x,y)},
  async click(x,y,button,count,holdKeys){
    _moveMouse(x,y);
    var rep=count||1;
    if(_wayland&&_checkYdotool()){
      _logFirstUse("click","ydotool");
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
      _logFirstUse("click","xdotool");
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
    if(_wayland&&_checkYdotool()){_logFirstUse("drag","ydotool");_exec("ydotool click 0x40")}
    else{_logFirstUse("drag","xdotool");_exec("xdotool mousedown 1")}
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
      _logFirstUse("drag","ydotool");
      _exec("ydotool click 0x40");
      _exec("ydotool mousemove --absolute 0 0");_cp.execSync("sleep 0.05");_exec("ydotool mousemove "+Math.round(end.x)+" "+Math.round(end.y));
      _cp.execSync("sleep 0.05");
      _exec("ydotool click 0x80");
    }else{
      _logFirstUse("drag","xdotool");
      _exec("xdotool mousedown 1");
      _exec("xdotool mousemove --sync "+Math.round(end.x)+" "+Math.round(end.y));
      _cp.execSync("sleep 0.05");
      _exec("xdotool mouseup 1");
    }
  },
  async scroll(x,y,horizontal,vertical){
    _moveMouse(x,y);
    if(_wayland&&_checkYdotool()){
      _logFirstUse("scroll","ydotool");
      if(vertical&&vertical!==0){var vamt=-Math.round(vertical);_exec("ydotool mousemove -w -- 0 "+vamt)}
      if(horizontal&&horizontal!==0){var hamt=Math.round(horizontal);_exec("ydotool mousemove -w -- "+hamt+" 0")}
    }else{
      _logFirstUse("scroll","xdotool");
      if(vertical&&vertical!==0){var vb=vertical>0?5:4;_exec("xdotool click --repeat "+Math.abs(Math.round(vertical))+" --delay 30 "+vb)}
      if(horizontal&&horizontal!==0){var hb=horizontal>0?7:6;_exec("xdotool click --repeat "+Math.abs(Math.round(horizontal))+" --delay 30 "+hb)}
    }
  },
  async key(combo,count){
    var n=count||1;
    if(_wayland&&_checkYdotool()){
      _logFirstUse("key","ydotool");
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
      _logFirstUse("key","xdotool");
      var mapped=combo.split("+").map(_mapKey).join("+");
      for(var i=0;i<n;i++){if(i>0)_cp.execSync("sleep 0.008");_exec("xdotool key --clearmodifiers "+mapped)}
    }
  },
  async holdKey(keyName,seconds){
    var secs=Math.min(seconds||0.5,10);
    if(_wayland&&_checkYdotool()){
      _logFirstUse("key","ydotool");
      var k=_mapKeyWayland(keyName);
      _exec("ydotool key "+k+":1");
      _cp.execSync("sleep "+secs);
      _exec("ydotool key "+k+":0");
    }else{
      _logFirstUse("key","xdotool");
      var k=_mapKey(keyName);
      _exec("xdotool keydown "+k);
      _cp.execSync("sleep "+secs);
      _exec("xdotool keyup "+k);
    }
  },
  async type(text,opts){
    if(_wayland&&_checkYdotool()){
      _logFirstUse("type","ydotool"+(opts&&opts.viaClipboard?" (clipboard)":""));
      if(opts&&opts.viaClipboard){
        _electron.clipboard.writeText(text,"clipboard");
        _exec("ydotool key 29:1 47:1 47:0 29:0");
      }else{
        _cp.execSync("ydotool type -- "+JSON.stringify(text),{timeout:15000});
      }
    }else{
      _logFirstUse("type","xdotool"+(opts&&opts.viaClipboard?" (clipboard)":""));
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