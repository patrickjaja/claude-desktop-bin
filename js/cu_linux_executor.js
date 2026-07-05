(function(){
var _cp=require("child_process"),_path=require("path"),_fs=require("fs"),_os=require("os"),_electron=require("electron");
function _exec(cmd){return _cp.execSync(cmd,{encoding:"utf-8",timeout:15000}).trim()}
function _execBuf(cmd){return _cp.execSync(cmd,{timeout:15000})}
function _isWayland(){var st=(process.env.XDG_SESSION_TYPE||"").toLowerCase();if(st==="wayland")return true;if(st==="x11")return false;return!!process.env.WAYLAND_DISPLAY}
var _wayland=_isWayland();
function _isWlroots(){return!!process.env.SWAYSOCK||!!process.env.HYPRLAND_INSTANCE_SIGNATURE||!!process.env.NIRI_SOCKET}
try{var _virt=_cp.execSync("systemd-detect-virt 2>/dev/null",{encoding:"utf-8",timeout:3000}).trim();globalThis.__isVM=_virt!=="none"&&_virt!==""}catch(e){globalThis.__isVM=!1}
if(globalThis.__isVM)console.log("[claude-cu] VM detected ("+_virt+") — teach overlay uses dark backdrop fallback");
var _cmdCache={};
function _hasCmd(cmd){if(_cmdCache[cmd]!==void 0)return _cmdCache[cmd];try{_exec("which "+cmd+" 2>/dev/null");_cmdCache[cmd]=true}catch(e){_cmdCache[cmd]=false}return _cmdCache[cmd]}
function _desktopId(){return(process.env.XDG_CURRENT_DESKTOP||"").toLowerCase()}
var _ydotoolOk=null;
function _checkYdotool(){if(_ydotoolOk!==null)return _ydotoolOk;if(!_hasCmd("ydotool")){_ydotoolOk=false;return false}try{_cp.execSync("pgrep -x ydotoold",{timeout:2000,stdio:"pipe"});_ydotoolOk=true}catch(e){var sock=(process.env.YDOTOOL_SOCKET||"")||((process.env.XDG_RUNTIME_DIR||"/tmp")+"/.ydotool_socket");try{_fs.accessSync(sock);_ydotoolOk=true}catch(se){console.warn("[claude-cu] ydotool found but ydotoold not running — falling back to x11-bridge (XWayland)");_ydotoolOk=false}}return _ydotoolOk}
// ── x11-bridge: first-party X11/XWayland backend (replaces xdotool/scrot/import/wmctrl) ──
// The binary is resolved in cu_mode_preamble.js into globalThis.__cuX11BridgeBin.
function _x11BridgeBin(){return process.env.X11_BRIDGE_BIN||globalThis.__cuX11BridgeBin}
function _x11Bridge(args){
  var bin=_x11BridgeBin();
  if(!bin)throw new Error("x11-bridge not available (globalThis.__cuX11BridgeBin unset — set X11_BRIDGE_BIN or install x11-bridge)");
  var res=_cp.execFileSync(bin,args,{encoding:"utf-8",timeout:15000,maxBuffer:16*1024*1024});
  var out=res.trim();
  return out?JSON.parse(out):null;
}
// Bridge-side monitor list (RandR names + root-window geometry). Used to map a
// root-coordinate region to a monitor name + monitor-relative coords for `zoom`.
var _x11ScreensCache=null;
function _x11BridgeScreens(){
  if(_x11ScreensCache!==null)return _x11ScreensCache;
  try{var s=_x11Bridge(["screens"]);_x11ScreensCache=Array.isArray(s)?s:[]}catch(e){console.warn("[claude-cu] x11-bridge screens failed: "+(e.message||e));_x11ScreensCache=[]}
  return _x11ScreensCache;
}
function _readClean(f){var buf=_fs.readFileSync(f);try{_fs.unlinkSync(f)}catch(e){}return buf.toString("base64")}
var _portalTokenPath=_path.join(_electron.app.getPath("userData"),"pipewire-restore-token");
var _portalPyCode="import sys,os,signal,subprocess\nTOKEN_FILE=os.environ.get('CLAUDE_PORTAL_TOKEN_PATH') or os.path.expanduser('~/.config/Claude/pipewire-restore-token')\nTIMEOUT_SECS=10\ndef main():\n    if len(sys.argv)<2:\n        print('Usage: gnome-portal-screenshot.py <output.png> [x y w h]',file=sys.stderr);return 1\n    output_path=sys.argv[1]\n    crop=tuple(int(x) for x in sys.argv[2:6]) if len(sys.argv)>=6 else None\n    try:\n        import gi\n        gi.require_version('Gst','1.0')\n        from gi.repository import GLib,Gio,Gst\n    except (ImportError,ValueError) as e:\n        print(f'[portal-screenshot] missing deps: {e}',file=sys.stderr);return 2\n    Gst.init(None)\n    restore_token=''\n    try:\n        with open(TOKEN_FILE) as f: restore_token=f.read().strip()\n    except FileNotFoundError: pass\n    bus=Gio.bus_get_sync(Gio.BusType.SESSION)\n    loop=GLib.MainLoop()\n    state={'node_id':None,'new_token':'','session':'','error':None,'done':False}\n    unique_name=bus.get_unique_name().replace('.','_').replace(':','')\n    counter=[0]\n    def next_token():\n        counter[0]+=1;return f'claude_{os.getpid()}_{counter[0]}'\n    def subscribe_response(handle_path,callback):\n        sub_id=[None]\n        def on_signal(_conn,_sender,_path,_iface,_sig,params):\n            bus.signal_unsubscribe(sub_id[0]);resp,results=params.unpack();callback(resp,results)\n        sub_id[0]=bus.signal_subscribe('org.freedesktop.portal.Desktop','org.freedesktop.portal.Request','Response',handle_path,None,0,on_signal);return sub_id[0]\n    def portal_call(method,args_variant):\n        return bus.call_sync('org.freedesktop.portal.Desktop','/org/freedesktop/portal/desktop','org.freedesktop.portal.ScreenCast',method,args_variant,None,0,TIMEOUT_SECS*1000,None)\n    def fail(msg):\n        state['error']=msg\n        if loop.is_running(): loop.quit()\n    def do_start():\n        ht=next_token();hp=f'/org/freedesktop/portal/desktop/request/{unique_name}/{ht}'\n        def on_start(resp,results):\n            if resp!=0: fail(f'Start rejected ({resp})');return\n            streams=results.get('streams',None);new_tok=results.get('restore_token','')\n            if new_tok: state['new_token']=new_tok\n            if streams:\n                sl=streams.unpack() if hasattr(streams,'unpack') else streams\n                if sl: state['node_id']=sl[0][0] if isinstance(sl[0],tuple) else sl[0]\n            state['done']=True;loop.quit()\n        subscribe_response(hp,on_start)\n        portal_call('Start',GLib.Variant('(osa{sv})',(state['session'],'',{'handle_token':GLib.Variant('s',ht)})))\n    def do_select():\n        ht=next_token();hp=f'/org/freedesktop/portal/desktop/request/{unique_name}/{ht}'\n        def on_select(resp,_results):\n            if resp!=0: fail(f'SelectSources rejected ({resp})');return\n            do_start()\n        subscribe_response(hp,on_select)\n        opts={'handle_token':GLib.Variant('s',ht),'types':GLib.Variant('u',1),'multiple':GLib.Variant('b',False),'persist_mode':GLib.Variant('u',2)}\n        if restore_token: opts['restore_token']=GLib.Variant('s',restore_token)\n        portal_call('SelectSources',GLib.Variant('(oa{sv})',(state['session'],opts)))\n    def do_create():\n        ht=next_token();st=f'claude_sess_{os.getpid()}'\n        hp=f'/org/freedesktop/portal/desktop/request/{unique_name}/{ht}'\n        def on_create(resp,results):\n            if resp!=0: fail(f'CreateSession rejected ({resp})');return\n            sh=results.get('session_handle','')\n            if not sh: fail('No session handle');return\n            state['session']=sh;do_select()\n        subscribe_response(hp,on_create)\n        portal_call('CreateSession',GLib.Variant('(a{sv})',({'handle_token':GLib.Variant('s',ht),'session_handle_token':GLib.Variant('s',st)},)))\n    GLib.timeout_add_seconds(TIMEOUT_SECS,lambda:(fail('timeout') if not state['done'] else None,False)[-1])\n    try: do_create();loop.run()\n    except Exception as e: fail(str(e))\n    if state['error']:\n        print(f'[portal-screenshot] {state[\"error\"]}',file=sys.stderr);return 1\n    if not state['node_id']:\n        print('[portal-screenshot] no PipeWire node',file=sys.stderr);return 1\n    if state['new_token']:\n        try:\n            os.makedirs(os.path.dirname(TOKEN_FILE),exist_ok=True)\n            with open(TOKEN_FILE,'w') as f: f.write(state['new_token'])\n        except OSError: pass\n    node_id=state['node_id']\n    try:\n        pipeline=Gst.parse_launch(f'pipewiresrc path={node_id} num-buffers=1 ! videoconvert ! pngenc ! filesink location=\"{output_path}\"')\n        pipeline.set_state(Gst.State.PLAYING)\n        gst_bus=pipeline.get_bus()\n        msg=gst_bus.timed_pop_filtered(5*Gst.SECOND,Gst.MessageType.EOS|Gst.MessageType.ERROR)\n        if msg and msg.type==Gst.MessageType.ERROR:\n            err,_=msg.parse_error();print(f'[portal-screenshot] GStreamer: {err.message}',file=sys.stderr)\n            pipeline.set_state(Gst.State.NULL);return 1\n        pipeline.set_state(Gst.State.NULL)\n    except Exception as e:\n        print(f'[portal-screenshot] GStreamer failed: {e}',file=sys.stderr);return 1\n    if not os.path.exists(output_path): return 1\n    if crop:\n        cx,cy,cw,ch=crop\n        try:\n            from gi.repository import GdkPixbuf\n            pb=GdkPixbuf.Pixbuf.new_from_file(output_path)\n            pw,ph=pb.get_width(),pb.get_height()\n            cx=min(cx,pw-1);cy=min(cy,ph-1);cw=min(cw,pw-cx);ch=min(ch,ph-cy)\n            cr=GdkPixbuf.Pixbuf.new(GdkPixbuf.Colorspace.RGB,pb.get_has_alpha(),8,cw,ch)\n            pb.copy_area(cx,cy,cw,ch,cr,0,0);cr.savev(output_path,'png',[],[])\n        except ImportError:\n            try: subprocess.run(['convert',output_path,'-crop',f'{cw}x{ch}+{cx}+{cy}','+repage',output_path],timeout=5,check=True,capture_output=True)\n            except Exception: pass\n    if state['session']:\n        try: bus.call_sync('org.freedesktop.portal.Desktop',state['session'],'org.freedesktop.portal.Session','Close',None,None,0,1000,None)\n        except Exception: pass\n    return 0\nif __name__=='__main__':\n    signal.signal(signal.SIGALRM,lambda *_:sys.exit(1));signal.alarm(TIMEOUT_SECS+5);sys.exit(main())";
function _hasPortalDeps(){return _hasCmd("python3")&&_hasCmd("gst-launch-1.0")}
function _hasPortalToken(){try{_fs.accessSync(_portalTokenPath);return true}catch(e){return false}}
async function _portalScreenshot(tmp,x,y,w,h){
  return new Promise(function(resolve){var ch=_cp.spawn("python3",["-",tmp,String(x),String(y),String(w),String(h)],{stdio:["pipe","pipe","pipe"],env:Object.assign({},process.env,{CLAUDE_PORTAL_TOKEN_PATH:_portalTokenPath})});ch.stdin.write(_portalPyCode);ch.stdin.end();var se="";ch.stderr.on("data",function(d){se+=d.toString()});var timer=setTimeout(function(){ch.kill("SIGKILL");resolve({status:1,stderr:"timeout"})},15000);ch.on("close",function(code){clearTimeout(timer);resolve({status:code,stderr:se})});ch.on("error",function(e){clearTimeout(timer);resolve({status:1,stderr:e.message})})});
}
function _findMonByPoint(px,py){
  var mons=_getMonitors();
  for(var i=0;i<mons.length;i++){var m=mons[i];if(px>=m.originX&&px<m.originX+m.width&&py>=m.originY&&py<m.originY+m.height)return m}
  for(var i=0;i<mons.length;i++){if(mons[i].isPrimary)return mons[i]}
  return mons[0];
}
// Map a root-coordinate region to the bridge monitor that contains its top-left,
// returning {name, x, y} where x/y are monitor-relative. Falls back to primary/first.
function _x11MonForRegion(x,y){
  var screens=_x11BridgeScreens();
  if(!screens.length)return null;
  var pick=null;
  for(var i=0;i<screens.length;i++){
    var g=screens[i].geometry||{};
    if(x>=g.x&&x<g.x+g.width&&y>=g.y&&y<g.y+g.height){pick=screens[i];break}
  }
  if(!pick){for(var j=0;j<screens.length;j++){if(screens[j].is_primary){pick=screens[j];break}}}
  if(!pick)pick=screens[0];
  var pg=pick.geometry||{x:0,y:0};
  return{name:pick.name||pick.id,x:x-pg.x,y:y-pg.y};
}
// Returns {base64, imgW, imgH, mimeType} where imgW/imgH are the EMITTED image's
// pixel dimensions (post-downscale) and mimeType is the produced format. Most
// tiers capture the region at native resolution (no downscale) and produce PNG,
// so imgW/imgH == the captured region size (w,h after scaleFactor) and
// mimeType=="image/png". The x11-bridge tier downscales (long edge <= 1568,
// total <= 1_150_000 px) and produces JPEG, so it overrides imgW/imgH with the
// bridge's returned width/height and mimeType with "image/jpeg". The handler
// uses imgW/imgH to map model image-pixel coordinates back to root pixels.
async function _captureRegion(x,y,w,h,sf){
  if(!sf){var _m=_findMonByPoint(x,y);sf=_m?_m.scaleFactor:1}
  if(sf&&sf!==1){x=Math.round(x*sf);y=Math.round(y*sf);w=Math.round(w*sf);h=Math.round(h*sf)}
  var tmp=_path.join(_os.tmpdir(),"claude-cu-"+Date.now()+"-"+Math.random().toString(36).slice(2)+".png");
  var _de=_desktopId();
  // Native (non-downscaling) tiers crop to exactly w x h at native resolution
  // and emit PNG.
  function _nativePng(b64){return{base64:b64,imgW:w,imgH:h,mimeType:"image/png"}}
  if(process.env.COWORK_SCREENSHOT_CMD){
    try{var cmd=process.env.COWORK_SCREENSHOT_CMD.replace(/\{FILE\}/g,tmp).replace(/\{X\}/g,x).replace(/\{Y\}/g,y).replace(/\{W\}/g,w).replace(/\{H\}/g,h);
    _cp.execSync(cmd,{timeout:15000});console.log("[claude-cu] screenshot: captured via COWORK_SCREENSHOT_CMD");return _nativePng(_readClean(tmp))}catch(e){console.warn("[claude-cu] COWORK_SCREENSHOT_CMD failed: "+e.message)}
  }
  if(_wayland&&_isWlroots()&&_hasCmd("grim")){
    try{_cp.execSync('grim -g "'+x+","+y+" "+w+"x"+h+'" "'+tmp+'"',{timeout:10000});console.log("[claude-cu] screenshot: captured via grim (wlroots)");return _nativePng(_readClean(tmp))}catch(e){console.warn("[claude-cu] grim failed: "+e.message)}
  }
  if(_wayland&&_de.indexOf("gnome")>=0&&_hasPortalToken()&&_hasPortalDeps()){
    try{var ret=await _portalScreenshot(tmp,x,y,w,h);
    if(ret.status===0&&_fs.existsSync(tmp)){console.log("[claude-cu] screenshot: captured via portal+pipewire (GNOME, restore token)");return _nativePng(_readClean(tmp))}
    if(ret.status===2){console.warn("[claude-cu] portal screenshot: missing python deps (python3-gi, gstreamer)")}
    else{console.warn("[claude-cu] portal screenshot failed (exit="+ret.status+"): "+(ret.stderr?ret.stderr.trim():""))}}catch(e){console.warn("[claude-cu] portal screenshot error: "+e.message)}
  }
  if(_wayland&&_de.indexOf("gnome")>=0&&_hasCmd("gnome-screenshot")){
    try{var _gstmp=_path.join(_os.tmpdir(),"claude-cu-gnome-"+Date.now()+".png");
    _cp.execSync('gnome-screenshot -f "'+_gstmp+'"',{timeout:10000});
    if(_fs.existsSync(_gstmp)){if(_hasCmd("convert")){try{_cp.execSync('convert "'+_gstmp+'" -crop '+w+"x"+h+"+"+x+"+"+y+' +repage "'+tmp+'"',{timeout:5000});try{_fs.unlinkSync(_gstmp)}catch(e){}console.log("[claude-cu] screenshot: captured via gnome-screenshot+convert (Wayland GNOME)");return _nativePng(_readClean(tmp))}catch(ce){try{_fs.renameSync(_gstmp,tmp)}catch(re){}console.log("[claude-cu] screenshot: captured via gnome-screenshot (Wayland GNOME, uncropped)");return _nativePng(_readClean(tmp))}}else{try{_fs.renameSync(_gstmp,tmp)}catch(re){}console.log("[claude-cu] screenshot: captured via gnome-screenshot (Wayland GNOME, uncropped)");return _nativePng(_readClean(tmp))}}
    }catch(e){console.warn("[claude-cu] gnome-screenshot (Wayland) failed: "+e.message)}
  }
  if(_wayland&&_de.indexOf("gnome")>=0&&_hasCmd("gdbus")){
    try{_cp.execSync("gdbus call --session --dest org.gnome.Shell.Screenshot --object-path /org/gnome/Shell/Screenshot --method org.gnome.Shell.Screenshot.ScreenshotArea "+x+" "+y+" "+w+" "+h+" false '"+tmp+"'",{timeout:10000});
    if(_fs.existsSync(tmp)){console.log("[claude-cu] screenshot: captured via gdbus (GNOME Shell Screenshot D-Bus)");return _nativePng(_readClean(tmp))}}catch(e){console.warn("[claude-cu] GNOME D-Bus screenshot failed: "+e.message)}
  }
  if(_wayland&&_de.indexOf("gnome")>=0&&!_hasPortalToken()&&_hasPortalDeps()){
    try{var ret=await _portalScreenshot(tmp,x,y,w,h);
    if(ret.status===0&&_fs.existsSync(tmp)){console.log("[claude-cu] screenshot: captured via portal+pipewire (GNOME, first-run)");return _nativePng(_readClean(tmp))}
    if(ret.status===2){console.warn("[claude-cu] portal screenshot: missing python deps (python3-gi, gstreamer)")}
    else{console.warn("[claude-cu] portal screenshot failed (exit="+ret.status+"): "+(ret.stderr?ret.stderr.trim():""))}}catch(e){console.warn("[claude-cu] portal screenshot error: "+e.message)}
  }
  if(_de.indexOf("kde")>=0&&_hasCmd("spectacle")){
    try{var stmp=_path.join(_os.tmpdir(),"claude-cu-spectacle-"+Date.now()+".png");
    _cp.execSync('spectacle -b -n -f -o "'+stmp+'"',{timeout:10000});
    if(_fs.existsSync(stmp)){try{_cp.execSync('convert "'+stmp+'" -crop '+w+"x"+h+"+"+x+"+"+y+' +repage "'+tmp+'"',{timeout:5000});try{_fs.unlinkSync(stmp)}catch(e){}console.log("[claude-cu] screenshot: captured via spectacle+convert (KDE)");return _nativePng(_readClean(tmp))}catch(ce){try{_fs.renameSync(stmp,tmp)}catch(re){}console.log("[claude-cu] screenshot: captured via spectacle (KDE, uncropped)");return _nativePng(_readClean(tmp))}}
    }catch(e){console.warn("[claude-cu] spectacle failed: "+e.message)}
  }
  // X11 (and XWayland fallback): single first-party tier — x11-bridge zoom.
  // The bridge returns inline base64 JPEG (quality 75) and its own width/height
  // (the DOWNSCALED emitted dims). We translate the root region to the containing
  // RandR monitor + monitor-relative coords, since the bridge's `zoom --display
  // <name>` expects monitor-relative x/y.
  if(!_wayland||_x11BridgeBin()){
    if(_x11BridgeBin()){
      try{
        var _mr=_x11MonForRegion(x,y);
        var _zargs=["zoom","--x",String(_mr?_mr.x:x),"--y",String(_mr?_mr.y:y),"--w",String(w),"--h",String(h)];
        if(_mr&&_mr.name){_zargs.push("--display",_mr.name)}
        var _zr=_x11Bridge(_zargs);
        if(_zr&&_zr.base64){console.log("[claude-cu] screenshot: captured via x11-bridge"+(_wayland?" (XWayland)":""));return{base64:_zr.base64,imgW:_zr.width||w,imgH:_zr.height||h,mimeType:"image/jpeg"}}
      }catch(e){console.warn("[claude-cu] x11-bridge zoom failed: "+(e.message||e))}
    }else if(!_wayland){
      // X11 session with no bridge: hard fail (no third-party fallback, per design).
      // The Electron desktopCapturer tier below is the only remaining last resort.
      console.error("[claude-cu] x11-bridge missing on X11 session — set X11_BRIDGE_BIN or install x11-bridge");
    }
  }
  try{var _sources=await _electron.desktopCapturer.getSources({types:["screen"],thumbnailSize:{width:w+x,height:h+y}});if(_sources&&_sources.length>0){var _img=_sources[0].thumbnail;if(_img&&!_img.isEmpty()){var _cropped=_img.crop({x:x,y:y,width:w,height:h});_fs.writeFileSync(tmp,_cropped.toPNG());console.log("[claude-cu] screenshot: captured via desktopCapturer (Electron fallback)");return _nativePng(_readClean(tmp))}}}catch(dce){console.warn("[claude-cu] desktopCapturer fallback failed: "+dce.message)}
  throw new Error("Screenshot failed — on X11 install x11-bridge (or set X11_BRIDGE_BIN); on Wayland install grim (wlroots) or set COWORK_SCREENSHOT_CMD.")
}
if(_wayland){console.log("[claude-cu] Wayland session detected — using native Wayland tools")}
(function(){
  var _de=_desktopId();var _wlr=_wayland?_isWlroots():false;
  var _isGnome=_de.indexOf("gnome")>=0;var _isKde=_de.indexOf("kde")>=0;
  var _isHypr=!!process.env.HYPRLAND_INSTANCE_SIGNATURE;var _isSway=!!process.env.SWAYSOCK;var _isNiri=!!process.env.NIRI_SOCKET;
  var _relevant=[];
  if(_wayland&&_wlr)_relevant.push("grim");
  if(_wayland&&_isGnome){_relevant.push("gst-launch-1.0");_relevant.push("gnome-screenshot");_relevant.push("gdbus")}
  if(_isKde){_relevant.push("spectacle");_relevant.push("convert")}
  if(_wayland)_relevant.push("ydotool");
  if(_isHypr)_relevant.push("hyprctl");
  if(_isSway){_relevant.push("swaymsg");_relevant.push("jq")}
  if(_isNiri)_relevant.push("niri");
  _relevant.push("xdg-open");
  var avail=_relevant.filter(function(t){return _hasCmd(t)});
  var missing=_relevant.filter(function(t){return !_hasCmd(t)});
  var _x11ok=!!_x11BridgeBin();
  console.log("[claude-cu] diagnostics: session="+(_wayland?"wayland":"x11")+" de="+(_de||"unknown")+" wlroots="+_wlr+" vm="+!!globalThis.__isVM);
  try{var _diagMons=_getMonitors();console.log("[claude-cu] diagnostics: displays=["+_diagMons.map(function(m){return m.label+"("+m.width+"x"+m.height+"+"+m.originX+"+"+m.originY+" sf="+m.scaleFactor+(m.isPrimary?" primary":"")+")"}).join(", ")+"]")}catch(me){}
  console.log("[claude-cu] diagnostics: available=["+avail.join(", ")+"]");
  if(missing.length)console.warn("[claude-cu] diagnostics: missing=["+missing.join(", ")+"] (install for full functionality)");
  console.log("[claude-cu] diagnostics: x11-bridge="+(_x11ok?"present ("+_x11BridgeBin()+")":"absent"));
  if(_wayland){
    var ydOk=_checkYdotool();
    console.log("[claude-cu] diagnostics: input-backend="+(ydOk?"ydotool":(_x11ok?"x11-bridge (XWayland fallback)":"none (install ydotool or x11-bridge)")));
  }else{
    console.log("[claude-cu] diagnostics: input-backend="+(_x11ok?"x11-bridge":"none (install x11-bridge)"));
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
  if(_x11ok&&(!_wayland||_x11ok))order.push("x11-bridge"+(_wayland?" (XWayland)":""));
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
    try{_logFirstUse("mouse","ydotool");_exec("ydotool mousemove --absolute 0 0");_cp.execSync("sleep 0.05");_exec("ydotool mousemove "+Math.round(x)+" "+Math.round(y));return}catch(e){console.warn("[claude-cu] ydotool mousemove failed, falling back to x11-bridge: "+e.message)}
  }else{
    if(_wayland&&!_checkYdotool())console.warn("[claude-cu] ydotool not available on Wayland, falling back to x11-bridge via XWayland");
  }
  _logFirstUse("mouse","x11-bridge");
  _x11Bridge(["pointer-move","--x",String(Math.round(x)),"--y",String(Math.round(y))]);
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
// Full-monitor capture. Returns {base64, imgW, imgH, mimeType, displayWidth,
// displayHeight, originX, originY} — imgW/imgH are the EMITTED image dims (which
// may be downscaled below the monitor's native size); displayWidth/displayHeight
// are the monitor's native logical size. The handler needs both to map model
// image-pixel coordinates back to root pixels.
async function _screenshotMon(mon){
  var cap=await _captureRegion(mon.originX,mon.originY,mon.width,mon.height,mon.scaleFactor||1);
  return{base64:cap.base64,imgW:cap.imgW,imgH:cap.imgH,mimeType:cap.mimeType,displayWidth:mon.width,displayHeight:mon.height,originX:mon.originX||0,originY:mon.originY||0};
}
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
  try{
    if(process.env.NIRI_SOCKET&&_hasCmd("niri")){
      var out=_exec("niri msg --json focused-window 2>/dev/null");
      var w=JSON.parse(out);
      if(w&&(w.app_id||w.title)){_logFirstUse("window","niri msg");return{bundleId:w.app_id||w.title,displayName:w.title||w.app_id}}
    }
  }catch(ne){}
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
  try{
    if(process.env.NIRI_SOCKET&&_hasCmd("niri")){
      console.log("[claude-cu] listRunningApps: using niri msg");
      var out=_exec("niri msg --json windows 2>/dev/null");
      var wins=JSON.parse(out);
      for(var i=0;i<wins.length;i++){
        var w=wins[i];
        var id=w.app_id||w.title;
        if(id&&!seen[id]){seen[id]=true;apps.push({bundleId:w.app_id||w.title,displayName:w.title||w.app_id})}
      }
      return apps;
    }
  }catch(ne){}
  return apps;
}
// Map an x11-bridge WindowInfo (snake_case) to the {bundleId,displayName} shape
// the executor's callers expect. Mirrors executor_linux.js normalizeBundleIdFromWindow.
function _bundleIdFromWindow(w){
  var cands=[w.desktop_file_name,w.resource_class,w.resource_name,w.id];
  for(var i=0;i<cands.length;i++){var c=cands[i];if(typeof c==="string"&&c.trim())return c.replace(/\.desktop$/i,"")}
  return null;
}
function _appRefFromWindow(w){
  if(!w)return null;
  var bid=_bundleIdFromWindow(w);
  if(!bid)return null;
  return{bundleId:bid,displayName:(typeof w.title==="string"&&w.title.trim())?w.title:bid};
}
// frontmost-app / app-under-point emit camelCase {bundleId,displayName} directly.
function _appRefFromCommand(result){
  if(!result||typeof result!=="object")return null;
  if(typeof result.bundleId!=="string"||typeof result.displayName!=="string")return null;
  return{bundleId:result.bundleId,displayName:result.displayName};
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
    var shot=await _screenshotMon(mon);
    // {base64, imgW, imgH, mimeType, displayWidth, displayHeight, originX, originY}
    return shot;
  },
  async resolvePrepareCapture(opts){
    var did=opts&&opts.preferredDisplayId;
    var mon=_findMon(did);
    var shot=await _screenshotMon(mon);
    return{base64:shot.base64,mimeType:shot.mimeType,width:shot.imgW,height:shot.imgH,displayWidth:mon.width,displayHeight:mon.height,displayId:mon.displayId,originX:mon.originX,originY:mon.originY,hidden:[]};
  },
  async zoom(rect,scale,displayId){
    var mon=displayId!=null?_findMon(displayId):_findMonByPoint(rect.x,rect.y);
    var sf=mon?mon.scaleFactor:1;
    console.log("[claude-cu] zoom: rect="+JSON.stringify(rect)+" scale="+scale+" displayId="+displayId+" mon="+((mon&&mon.label)||"?")+" sf="+sf);
    var cap=await _captureRegion(rect.x,rect.y,rect.w,rect.h,sf);
    // {base64, imgW, imgH, mimeType}
    return cap;
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
    if(_wayland&&_checkYdotool()){return _listRunningAppsWayland()}
    if(_wayland&&!_x11BridgeBin()){return _listRunningAppsWayland()}
    // X11 / XWayland: enumerate via x11-bridge windows (EWMH).
    try{
      _logFirstUse("app","x11-bridge");
      console.log("[claude-cu] listRunningApps: using x11-bridge windows");
      var wins=_x11Bridge(["windows"]);
      var apps=[],seen={};
      if(Array.isArray(wins)){
        for(var i=0;i<wins.length;i++){
          var w=wins[i];
          if(w.is_minimized===true)continue;
          if(w.is_visible===false)continue;
          var ref=_appRefFromWindow(w);
          if(ref&&!seen[ref.bundleId]){seen[ref.bundleId]=true;apps.push(ref)}
        }
      }
      return apps;
    }catch(e){console.warn("[claude-cu] x11-bridge windows failed: "+(e.message||e));return[]}
  },
  async getFrontmostApp(){
    if(_wayland&&_checkYdotool()){return _getActiveWindowWayland()}
    if(_wayland&&!_x11BridgeBin()){return _getActiveWindowWayland()}
    try{
      _logFirstUse("window","x11-bridge");
      // frontmost-app emits camelCase {bundleId,displayName}.
      return _appRefFromCommand(_x11Bridge(["frontmost-app"]));
    }catch(e){return null}
  },
  async appUnderPoint(x,y){
    if(_wayland&&_checkYdotool())return null;
    if(_wayland&&!_x11BridgeBin())return null;
    try{
      return _appRefFromCommand(_x11Bridge(["app-under-point","--x",String(Math.round(x)),"--y",String(Math.round(y))]));
    }catch(e){return null}
  },
  async getAppIcon(appPath){return null},
  async openApp(name){
    var _appDirs=["/usr/share/applications",_path.join(_os.homedir(),".local/share/applications"),"/var/lib/flatpak/exports/share/applications",_path.join(_os.homedir(),".local/share/flatpak/exports/share/applications")];
    // Parse all .desktop entries into {name, dfn, exec} once so we can both
    // resolve the launch command and, on failure, suggest close matches.
    function _allEntries(){
      var out=[];
      for(var d=0;d<_appDirs.length;d++){
        try{
          var files=_fs.readdirSync(_appDirs[d]);
          for(var i=0;i<files.length;i++){
            if(files[i].indexOf(".desktop")===-1)continue;
            try{
              var content=_fs.readFileSync(_path.join(_appDirs[d],files[i]),"utf-8");
              var nameMatch=content.match(/^Name=(.+)$/m);
              var execMatch=content.match(/^Exec=(\S+)/m);
              if(nameMatch&&execMatch){
                out.push({name:nameMatch[1].trim(),dfn:files[i].replace(/\.desktop$/,""),exec:execMatch[1].replace(/%.*/,"").trim()});
              }
            }catch(fe){}
          }
        }catch(de){}
      }
      return out;
    }
    function _resolveApp(n,entries){
      var nl=n.toLowerCase();
      for(var i=0;i<entries.length;i++){
        var e=entries[i];
        if(e.name.toLowerCase()===nl||e.dfn.toLowerCase()===nl||_path.basename(e.exec).toLowerCase()===nl)return e.exec;
      }
      return null;
    }
    // Offer up to 3 close .desktop names for an unresolved request: prefer
    // substring hits, then fall back to shared-prefix overlap (>=3 chars) so a
    // typo like "Chromixq" still surfaces "Chromium".
    function _suggest(nl,entries){
      if(!nl)return[];
      var sub=[],pre=[];
      function _shared(a,b){var n=Math.min(a.length,b.length),k=0;while(k<n&&a[k]===b[k])k++;return k}
      for(var i=0;i<entries.length;i++){
        var nm=entries[i].name,en=nm.toLowerCase(),ed=entries[i].dfn.toLowerCase();
        if(en.indexOf(nl)>=0||nl.indexOf(en)>=0||ed.indexOf(nl)>=0){if(sub.indexOf(nm)<0)sub.push(nm);continue}
        if(_shared(en,nl)>=3||_shared(ed,nl)>=3){if(pre.indexOf(nm)<0)pre.push(nm)}
      }
      return sub.concat(pre).slice(0,3);
    }
    // Bridge available only on X11 / XWayland sessions (same gate the other
    // window helpers use). On Wayland-native (ydotool, or no bridge) we keep the
    // legacy launch-only behavior and report {action:"launched"} without polling.
    var _bridgeOk=(!_wayland||_x11BridgeBin())&&!(_wayland&&_checkYdotool());
    // Normalize the requested string for case-insensitive matching, stripping a
    // trailing .desktop so "firefox.desktop" and "firefox" both work.
    function _norm(s){return typeof s==="string"?s.trim().toLowerCase().replace(/\.desktop$/,""):""}
    // Rank an existing window against the request. Exact desktop_file_name /
    // resource_class / resource_name match ranks highest (3), title-prefix
    // lowest (1); 0 = no match. Dock/desktop windows are skipped by the caller.
    function _matchScore(w,nl){
      if(!nl)return 0;
      var dfn=_norm(w.desktop_file_name),rc=_norm(w.resource_class),rn=_norm(w.resource_name);
      if(dfn===nl||rc===nl||rn===nl)return 3;
      // partial class/name containment (e.g. request "code", class "Code")
      if((dfn&&dfn.indexOf(nl)>=0)||(rc&&rc.indexOf(nl)>=0)||(rn&&rn.indexOf(nl)>=0))return 2;
      var title=typeof w.title==="string"?w.title.trim().toLowerCase():"";
      if(title&&title.indexOf(nl)===0)return 1;
      return 0;
    }
    function _findWindow(nl){
      var wins;
      try{wins=_x11Bridge(["windows"])}catch(e){console.warn("[claude-cu] openApp: bridge windows failed: "+(e.message||e));return null}
      if(!Array.isArray(wins))return null;
      var best=null,bestScore=0;
      for(var i=0;i<wins.length;i++){
        var w=wins[i];
        if(w.is_dock===true||w.is_desktop===true)continue;
        var s=_matchScore(w,nl);
        // Prefer higher score; tie-break toward the active window.
        if(s>bestScore||(s>0&&s===bestScore&&w.is_active===true&&(!best||best.is_active!==true))){best=w;bestScore=s}
      }
      return best;
    }
    function _activate(w){
      var wid=String(w.id);
      _x11Bridge(["activate-window","--window",wid]);
      var _bid=_bundleIdFromWindow(w)||wid;
      var _title=(typeof w.title==="string"&&w.title.trim())?w.title:_bid;
      return{action:"activated",app:_bid,windowTitle:_title};
    }
    var nl=_norm(name);
    // 1) Existing window? Activate it — no launch, no duplicate instance.
    if(_bridgeOk&&nl){
      var existing=_findWindow(nl);
      if(existing){
        console.log("[claude-cu] openApp: activating existing window for "+name+" (id "+existing.id+")");
        return _activate(existing);
      }
    }
    // 2) Resolve + launch. If the name doesn't resolve to a .desktop entry and
    // doesn't look like a file/URL, refuse and suggest close matches instead of
    // xdg-open'ing garbage.
    var entries=_allEntries();
    var resolved=_resolveApp(name,entries);
    var _looksLikePathOrUrl=/^[a-z][a-z0-9+.-]*:\/\//i.test(name)||name.indexOf("/")>=0||name.indexOf(".")>=0;
    if(!resolved&&!_looksLikePathOrUrl){
      var cands=_suggest(nl,entries);
      return{action:"not_found",app:name,suggestions:cands,isError:true};
    }
    if(!resolved){
      // Path/URL: hand to xdg-open and return — polling for a matching window is
      // meaningless (it may open a tab in an already-running handler).
      console.log("[claude-cu] openApp: name looks like a path/URL — setsid xdg-open "+name);
      try{_cp.exec("setsid xdg-open "+JSON.stringify(name)+" >/dev/null 2>&1")}
      catch(e2){throw new Error("Could not open "+name)}
      // xdg-open may open a tab in an already-running handler; we never verify a
      // window, so report the neutral "opened" (handler -> "Opened <name>").
      return{action:"opened",app:name};
    }
    try{
      console.log("[claude-cu] openApp: launching via setsid "+resolved);
      _cp.exec("setsid "+JSON.stringify(resolved)+" >/dev/null 2>&1");
    }catch(e){
      try{console.log("[claude-cu] openApp: fallback to xdg-open "+name);_cp.exec("setsid xdg-open "+JSON.stringify(name)+" >/dev/null 2>&1")}
      catch(e2){throw new Error("Could not open "+name+" (resolved to "+resolved+")")}
    }
    // 3) On the bridge path, poll briefly for a matching new window and activate
    // it. Slow-starting apps that never show a window within the budget are NOT
    // an error — return launch_attempted so the model knows to screenshot.
    if(_bridgeOk&&nl){
      var _deadline=Date.now()+5000;
      while(Date.now()<_deadline){
        try{_cp.execSync("sleep 0.5")}catch(se){}
        var appeared=_findWindow(nl);
        if(appeared){
          console.log("[claude-cu] openApp: new window appeared for "+name+" (id "+appeared.id+")");
          var r=_activate(appeared);r.action="launched";return r;
        }
      }
      return{action:"launch_attempted",app:name,note:"no window appeared within 5s"};
    }
    // Wayland-native / non-bridge fallback (GNOME Wayland, wlroots): launch-only,
    // no window tracking — the bridge windows/activate-window subcommands don't
    // exist here. Distinct "opened" action so the handler emits the original
    // "Opened app" text byte-for-byte, unchanged from before this feature.
    return{action:"opened",app:name};
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
      _logFirstUse("click","x11-bridge");
      var btnName={left:"left",right:"right",middle:"middle"}[button]||"left";
      var _cargs=["pointer-click","--x",String(Math.round(x)),"--y",String(Math.round(y)),"--button",btnName,"--count",String(rep)];
      if(holdKeys&&holdKeys.length>0){for(var i=0;i<holdKeys.length;i++){_cargs.push("--modifier",holdKeys[i])}}
      _x11Bridge(_cargs);
    }
  },
  async mouseDown(){
    if(_wayland&&_checkYdotool()){_logFirstUse("drag","ydotool");_exec("ydotool click 0x40")}
    else{_logFirstUse("drag","x11-bridge");_x11Bridge(["left-mouse-down"])}
  },
  async mouseUp(){
    if(_wayland&&_checkYdotool()){_exec("ydotool click 0x80")}
    else{_x11Bridge(["left-mouse-up"])}
  },
  async getCursorPosition(){
    var p=_electron.screen.getCursorScreenPoint();
    return{x:p.x,y:p.y};
  },
  async drag(start,end){
    if(_wayland&&_checkYdotool()){
      if(start)_moveMouse(start.x,start.y);
      _logFirstUse("drag","ydotool");
      _exec("ydotool click 0x40");
      _exec("ydotool mousemove --absolute 0 0");_cp.execSync("sleep 0.05");_exec("ydotool mousemove "+Math.round(end.x)+" "+Math.round(end.y));
      _cp.execSync("sleep 0.05");
      _exec("ydotool click 0x80");
    }else{
      _logFirstUse("drag","x11-bridge");
      var fromX=start?Math.round(start.x):Math.round(_electron.screen.getCursorScreenPoint().x);
      var fromY=start?Math.round(start.y):Math.round(_electron.screen.getCursorScreenPoint().y);
      _x11Bridge(["pointer-drag","--from-x",String(fromX),"--from-y",String(fromY),"--to-x",String(Math.round(end.x)),"--to-y",String(Math.round(end.y))]);
    }
  },
  async scroll(x,y,horizontal,vertical){
    _moveMouse(x,y);
    if(_wayland&&_checkYdotool()){
      _logFirstUse("scroll","ydotool");
      if(vertical&&vertical!==0){var vamt=-Math.round(vertical);_exec("ydotool mousemove -w -- 0 "+vamt)}
      if(horizontal&&horizontal!==0){var hamt=Math.round(horizontal);_exec("ydotool mousemove -w -- "+hamt+" 0")}
    }else{
      _logFirstUse("scroll","x11-bridge");
      var dx=horizontal?Math.round(horizontal):0;
      var dy=vertical?Math.round(vertical):0;
      if(dx!==0||dy!==0){_x11Bridge(["pointer-scroll","--x",String(Math.round(x)),"--y",String(Math.round(y)),"--dx",String(dx),"--dy",String(dy)])}
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
      // x11-bridge parses the CU key-spec grammar itself — pass the raw combo through.
      _logFirstUse("key","x11-bridge");
      var _kargs=["key-sequence","--keys",combo];
      if(n>1){_kargs.push("--repeat",String(n))}
      _x11Bridge(_kargs);
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
      _logFirstUse("key","x11-bridge");
      _x11Bridge(["hold-key","--key",keyName,"--duration-ms",String(Math.round(secs*1000))]);
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
      _logFirstUse("type","x11-bridge"+(opts&&opts.viaClipboard?" (clipboard)":""));
      if(opts&&opts.viaClipboard){
        _electron.clipboard.writeText(text,"clipboard");
        _x11Bridge(["key-sequence","--keys","ctrl+v"]);
      }else{
        _x11Bridge(["type","--text",text]);
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
