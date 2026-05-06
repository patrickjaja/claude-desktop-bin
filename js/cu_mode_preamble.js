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
  var _reason;
  if(envMode)_reason=" (CLAUDE_CU_MODE set)";
  else if(autoMode==="kwin-wayland")_reason=" (auto: KDE Wayland + kwin-portal-bridge at "+_resolvedBin+", "+_kwinVer+")";
  else if(_isKdeWayland&&!_kwinOk)_reason=" (auto: cross-distro fallback; KWin "+(_kwinVer||"unknown")+" < 6.6)";
  else _reason=" (auto: cross-distro fallback)";
  console.log("[claude-cu] mode="+_mode+_reason);
})();