(function(){
  var envMode=process.env.CLAUDE_CU_MODE;
  var autoMode="regular";
  if(process.env.XDG_SESSION_DESKTOP==="KDE"&&process.env.XDG_SESSION_TYPE==="wayland"){
    var _fs=require("fs"),_path=require("path");
    var _explicit=process.env.KWIN_PORTAL_BRIDGE_BIN;
    var _found=!1;
    if(_explicit){try{_fs.accessSync(_explicit,_fs.constants.X_OK);_found=!0}catch(e){}}
    else{
      var _paths=(process.env.PATH||"").split(_path.delimiter);
      for(var _i=0;_i<_paths.length&&!_found;_i++){
        if(!_paths[_i])continue;
        try{_fs.accessSync(_path.join(_paths[_i],"kwin-portal-bridge"),_fs.constants.X_OK);_found=!0}catch(e){}
      }
    }
    if(_found)autoMode="kwin-wayland";
  }
  var _mode=envMode||autoMode;
  globalThis.__cuKwinMode=_mode==="kwin-wayland";
  console.log("[claude-cu] mode="+_mode+(envMode?" (CLAUDE_CU_MODE set)":autoMode==="kwin-wayland"?" (auto: KDE Wayland + kwin-portal-bridge on PATH)":" (auto: cross-distro fallback)"));
})();