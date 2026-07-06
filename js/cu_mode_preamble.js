(function(){
  var envMode=process.env.CLAUDE_CU_MODE;
  var autoMode="regular";
  var _kwinVer="";
  var _kwinOk=!1;
  var _isKdeWayland=process.env.XDG_SESSION_DESKTOP==="KDE"&&process.env.XDG_SESSION_TYPE==="wayland";
  var _resolvedBin="";
  if(_isKdeWayland){
    try{
      var _cp=require("child_process");
      var _raw=_cp.execSync("kwin_wayland --version",{encoding:"utf8",timeout:2000,stdio:["ignore","pipe","ignore"]}).toString();
      var _m=_raw.match(/(\d+)\.(\d+)(?:\.(\d+))?/);
      if(_m){_kwinVer=_m[0];var _maj=parseInt(_m[1],10),_min=parseInt(_m[2],10);_kwinOk=_maj>6||(_maj===6&&_min>=6)}
    }catch(e){}
  }
  if(_kwinOk){
    var _fs=require("fs"),_path=require("path");
    var _explicit=process.env.KWIN_PORTAL_BRIDGE_BIN;
    var _found=!1;
    if(_explicit){try{_fs.accessSync(_explicit,_fs.constants.X_OK);_found=!0;_resolvedBin=_explicit}catch(e){}}
    if(!_found){
      var _bundled=_path.join(process.resourcesPath,"kwin-portal-bridge");
      try{_fs.accessSync(_bundled,_fs.constants.X_OK);_found=!0;_resolvedBin=_bundled}catch(e){}
    }
    if(!_found){
      var _paths=(process.env.PATH||"").split(_path.delimiter);
      for(var _i=0;_i<_paths.length&&!_found;_i++){
        if(!_paths[_i])continue;
        var _candidate=_path.join(_paths[_i],"kwin-portal-bridge");
        try{_fs.accessSync(_candidate,_fs.constants.X_OK);_found=!0;_resolvedBin=_candidate}catch(e){}
      }
    }
    if(_found){autoMode="kwin-wayland";globalThis.__cuKwinBridgeBin=_resolvedBin}
  }
  var _mode=envMode||autoMode;
  globalThis.__cuKwinMode=_mode==="kwin-wayland";
  // Resolve x11-bridge for the regular (non-kwin-wayland) executor. Used on X11
  // sessions and as the XWayland input/screenshot backend on Wayland sessions
  // where ydotool is unavailable. Skipped in kwin-wayland mode (that path uses
  // kwin-portal-bridge). Priority: X11_BRIDGE_BIN env → process.resourcesPath →
  // each $PATH dir; verified executable via X_OK.
  if(!globalThis.__cuKwinMode){
    var _sessType=(process.env.XDG_SESSION_TYPE||"").toLowerCase();
    var _sessionCouldNeedX11=_sessType==="x11"||_sessType==="wayland"||!!process.env.WAYLAND_DISPLAY||!!process.env.DISPLAY;
    if(_sessionCouldNeedX11){
      var _xfs=require("fs"),_xpath=require("path");
      var _xbFound=!1,_xbBin="";
      var _xbExplicit=process.env.X11_BRIDGE_BIN;
      if(_xbExplicit){try{_xfs.accessSync(_xbExplicit,_xfs.constants.X_OK);_xbFound=!0;_xbBin=_xbExplicit}catch(e){}}
      if(!_xbFound){
        var _xbBundled=_xpath.join(process.resourcesPath,"x11-bridge");
        try{_xfs.accessSync(_xbBundled,_xfs.constants.X_OK);_xbFound=!0;_xbBin=_xbBundled}catch(e){}
      }
      if(!_xbFound){
        var _xbPaths=(process.env.PATH||"").split(_xpath.delimiter);
        for(var _xbi=0;_xbi<_xbPaths.length&&!_xbFound;_xbi++){
          if(!_xbPaths[_xbi])continue;
          var _xbCandidate=_xpath.join(_xbPaths[_xbi],"x11-bridge");
          try{_xfs.accessSync(_xbCandidate,_xfs.constants.X_OK);_xbFound=!0;_xbBin=_xbCandidate}catch(e){}
        }
      }
      if(_xbFound){globalThis.__cuX11BridgeBin=_xbBin;console.log("[claude-cu] x11-bridge resolved at "+_xbBin)}
      else console.log("[claude-cu] x11-bridge not found (X11 input/screenshot + XWayland fallback unavailable)");
    }
    // Resolve wlroots-bridge (Sway/Hyprland/Niri) and gnome-portal-bridge (GNOME
    // Wayland) — the first-party CU backends for those Wayland session types.
    // Priority per bridge: <ENV>_BRIDGE_BIN → process.resourcesPath → each $PATH
    // dir; verified executable via X_OK. Resolution is gated on session type so
    // we don't probe binaries irrelevant to the running compositor.
    var _wlSess=_sessType==="wayland"||!!process.env.WAYLAND_DISPLAY;
    if(_wlSess){
      var _brfs=require("fs"),_brpath=require("path");
      function _resolveBridge(name,envVar){
        var _explicit=process.env[envVar];
        if(_explicit){try{_brfs.accessSync(_explicit,_brfs.constants.X_OK);return _explicit}catch(e){}}
        try{var _b=_brpath.join(process.resourcesPath,name);_brfs.accessSync(_b,_brfs.constants.X_OK);return _b}catch(e){}
        var _dirs=(process.env.PATH||"").split(_brpath.delimiter);
        for(var _di=0;_di<_dirs.length;_di++){
          if(!_dirs[_di])continue;
          try{var _c=_brpath.join(_dirs[_di],name);_brfs.accessSync(_c,_brfs.constants.X_OK);return _c}catch(e){}
        }
        return"";
      }
      var _isWlroots=!!process.env.SWAYSOCK||!!process.env.HYPRLAND_INSTANCE_SIGNATURE||!!process.env.NIRI_SOCKET;
      var _isGnome=(process.env.XDG_CURRENT_DESKTOP||"").toLowerCase().indexOf("gnome")>=0;
      if(_isWlroots){
        var _wlrBin=_resolveBridge("wlroots-bridge","WLROOTS_BRIDGE_BIN");
        if(_wlrBin){globalThis.__cuWlrootsBridgeBin=_wlrBin;console.log("[claude-cu] wlroots-bridge resolved at "+_wlrBin)}
        else console.log("[claude-cu] wlroots-bridge not found (wlroots-Wayland CU input/screenshot unavailable)");
      }
      if(_isGnome){
        var _gnBin=_resolveBridge("gnome-portal-bridge","GNOME_PORTAL_BRIDGE_BIN");
        if(_gnBin){globalThis.__cuGnomeBridgeBin=_gnBin;console.log("[claude-cu] gnome-portal-bridge resolved at "+_gnBin)}
        else console.log("[claude-cu] gnome-portal-bridge not found (GNOME-Wayland CU input/screenshot unavailable)");
      }
    }
  }
  var _reason;
  if(envMode)_reason=" (CLAUDE_CU_MODE set)";
  else if(autoMode==="kwin-wayland")_reason=" (auto: KDE Wayland + kwin-portal-bridge at "+_resolvedBin+", "+_kwinVer+")";
  else if(_isKdeWayland&&!_kwinOk)_reason=" (auto: cross-distro fallback; KWin "+(_kwinVer||"unknown")+" < 6.6)";
  else _reason=" (auto: cross-distro fallback)";
  console.log("[claude-cu] mode="+_mode+_reason);
})();