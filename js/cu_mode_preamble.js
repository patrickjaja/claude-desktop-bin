(function(){
// ── diagnostics sink ─────────────────────────────────────────────────────────
// The official .deb build DISCARDS console/process.stdout writes in the main
// process (the fds themselves are healthy - proven 2026-07-06 by writing into
// /proc/<mainpid>/fd/1 from a child while console.log in the same process
// produced nothing). So diagnostics go through __cdbDiag: raw fs.writeSync to
// fd 2 (reaches a terminal launch) plus a tee into userData/logs/
// claude-patches.log (profile/3p-aware, 2 MiB rotation). Never throws.
if(!globalThis.__cdbDiag){globalThis.__cdbDiag=function(){var s="";try{var i,a=[];for(i=0;i<arguments.length;i++){var x=arguments[i];if(typeof x==="string")a.push(x);else{try{a.push(JSON.stringify(x))}catch(e1){a.push(String(x))}}}s=a.join(" ")}catch(e2){}if(!s)return;try{require("fs").writeSync(2,s+"\n")}catch(e3){}try{var p=require("path"),fs=require("fs");if(!globalThis.__cdbDiagDir){globalThis.__cdbDiagDir=p.join(require("electron").app.getPath("userData"),"logs");fs.mkdirSync(globalThis.__cdbDiagDir,{recursive:!0})}var f=p.join(globalThis.__cdbDiagDir,"claude-patches.log");try{if(fs.statSync(f).size>2097152)fs.renameSync(f,f+".old")}catch(e4){}fs.appendFileSync(f,new Date().toISOString()+" "+s+"\n")}catch(e5){}};}
// ── bundled-bridge resolver ──────────────────────────────────────────────────
// All four bridges ship at a FIXED location inside the package - the same
// resources/ dir where upstream keeps its own bundled binaries
// (cowork-linux-helper, smol images, virtiofsd). So resolution is simply:
// <envVar> override (NixOS GNOME native build, debugging) → bundled dir.
// No $PATH scanning - a missing bundled bridge is a packaging bug that must
// fail loud, not be papered over by a stray system binary. The dir is
// process.resourcesPath: the app.asar is exe-adjacent in every install
// (Electron's OnlyLoadAppFromAsar autoload), so Electron resolves it natively.
// WHICH bridge to resolve is decided by SESSION detection below, not here.
  var _cdbBridgeDir=process.resourcesPath;
  function _cdbResolveBin(name,envVar){
    var _rfs=require("fs"),_rp=require("path");
    function _ok(c){try{_rfs.accessSync(c,_rfs.constants.X_OK);return!0}catch(e){return!1}}
    var _x=envVar?process.env[envVar]:"";
    if(_x&&_ok(_x))return _x;
    var _b=_rp.join(_cdbBridgeDir,name);
    return _ok(_b)?_b:"";
  }
  var envMode=process.env.CLAUDE_CU_MODE;
  var autoMode="regular";
  var _kwinVer="";
  var _kwinOk=!1;
  // KDE-Wayland detection must match the DOWNSTREAM DE detection in
  // cu_linux_executor.js (XDG_CURRENT_DESKTOP, lowercased substring) or the two
  // disagree: a session whose XDG_CURRENT_DESKTOP contains KDE but whose
  // XDG_SESSION_DESKTOP is "plasma"/unset (SDDM/DM-dependent, unreliable) would
  // route past the kwin-portal-bridge into the "exotic" ydotool/x11-bridge
  // fallback while the diagnostics still say de=kde (issue #194). Key off
  // XDG_CURRENT_DESKTOP (which Plasma reliably sets to "KDE"), case-insensitive
  // substring, and accept WAYLAND_DISPLAY as a Wayland signal since
  // XDG_SESSION_TYPE is not always exported.
  var _curDesk=(process.env.XDG_CURRENT_DESKTOP||"").toLowerCase();
  var _isWaylandSess=process.env.XDG_SESSION_TYPE==="wayland"||!!process.env.WAYLAND_DISPLAY;
  var _isKdeWayland=_curDesk.indexOf("kde")>=0&&_isWaylandSess;
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
    _resolvedBin=_cdbResolveBin("kwin-portal-bridge","KWIN_PORTAL_BRIDGE_BIN");
    if(_resolvedBin){autoMode="kwin-wayland";globalThis.__cuKwinBridgeBin=_resolvedBin}
  }
  var _mode=envMode||autoMode;
  globalThis.__cuKwinMode=_mode==="kwin-wayland";
  // Resolve x11-bridge for the regular (non-kwin-wayland) executor. Used on X11
  // sessions and as the XWayland input/screenshot backend on Wayland sessions
  // where ydotool is unavailable. Skipped in kwin-wayland mode (that path uses
  // kwin-portal-bridge). Priority: X11_BRIDGE_BIN env → bundled resources dir →
  // each $PATH dir; verified executable via X_OK.
  if(!globalThis.__cuKwinMode){
    var _sessType=(process.env.XDG_SESSION_TYPE||"").toLowerCase();
    var _sessionCouldNeedX11=_sessType==="x11"||_sessType==="wayland"||!!process.env.WAYLAND_DISPLAY||!!process.env.DISPLAY;
    if(_sessionCouldNeedX11){
      var _xbBin=_cdbResolveBin("x11-bridge","X11_BRIDGE_BIN");
      if(_xbBin){globalThis.__cuX11BridgeBin=_xbBin;globalThis.__cdbDiag("[claude-cu] x11-bridge resolved at "+_xbBin)}
      else globalThis.__cdbDiag("[claude-cu] x11-bridge not found (X11 input/screenshot + XWayland fallback unavailable)");
    }
    // Resolve wlroots-bridge (Sway/Hyprland/Niri) and gnome-portal-bridge (GNOME
    // Wayland) — the first-party CU backends for those Wayland session types.
    // Priority per bridge: <ENV>_BRIDGE_BIN → bundled resources dir → each $PATH
    // dir; verified executable via X_OK. Resolution is gated on session type so
    // we don't probe binaries irrelevant to the running compositor.
    var _wlSess=_sessType==="wayland"||!!process.env.WAYLAND_DISPLAY;
    if(_wlSess){
      var _isWlroots=!!process.env.SWAYSOCK||!!process.env.HYPRLAND_INSTANCE_SIGNATURE||!!process.env.NIRI_SOCKET;
      var _isGnome=(process.env.XDG_CURRENT_DESKTOP||"").toLowerCase().indexOf("gnome")>=0;
      if(_isWlroots){
        var _wlrBin=_cdbResolveBin("wlroots-bridge","WLROOTS_BRIDGE_BIN");
        if(_wlrBin){globalThis.__cuWlrootsBridgeBin=_wlrBin;globalThis.__cdbDiag("[claude-cu] wlroots-bridge resolved at "+_wlrBin)}
        else globalThis.__cdbDiag("[claude-cu] wlroots-bridge not found (wlroots-Wayland CU input/screenshot unavailable)");
      }
      if(_isGnome){
        var _gnBin=_cdbResolveBin("gnome-portal-bridge","GNOME_PORTAL_BRIDGE_BIN");
        if(_gnBin){globalThis.__cuGnomeBridgeBin=_gnBin;globalThis.__cdbDiag("[claude-cu] gnome-portal-bridge resolved at "+_gnBin)}
        else globalThis.__cdbDiag("[claude-cu] gnome-portal-bridge not found (GNOME-Wayland CU input/screenshot unavailable)");
      }
    }
  }
  var _reason;
  if(envMode)_reason=" (CLAUDE_CU_MODE set)";
  else if(autoMode==="kwin-wayland")_reason=" (auto: KDE Wayland + kwin-portal-bridge at "+_resolvedBin+", "+_kwinVer+")";
  else if(_isKdeWayland&&!_kwinOk)_reason=" (auto: cross-distro fallback; KWin "+(_kwinVer||"unknown")+" < 6.6)";
  else _reason=" (auto: cross-distro fallback)";
  globalThis.__cdbDiag("[claude-cu] mode="+_mode+_reason);
})();