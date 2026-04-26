# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
#
# Profile-aware URL handler routing for SSO callbacks.
#
# Problem: claude:// URL scheme is registered system-wide and points to the
# default profile's .desktop file. When a named profile (e.g. claude-desktop-work)
# initiates SSO, the auth callback URL fires the system handler, which launches
# the default profile and consumes the auth token there -- breaking login.
#
# Fix: hook shell.openExternal in the main process. When a profiled instance
# (CLAUDE_PROFILE is set) opens an auth-ish URL, write a marker file at
# $XDG_RUNTIME_DIR/claude-desktop-pending-auth-<profile> with a timestamp.
# The launcher reads these markers when it receives a claude:// URL with no
# explicit profile, picks the most recent (within 5 min), and re-execs with
# --profile=<name>. Electron's second-instance event then delivers the URL
# to the running profile.
#
# Marker is only written for URLs matching auth/oauth/sso/login/accounts to
# avoid misrouting from unrelated link clicks. Limitations are documented in
# README.md (Multiple Profiles section).
#
# Break risk: VERY LOW -- monkey-patches only public stable Electron API
# (shell.openExternal). Falls back to no-op if the original isn't a function.

import std/[os, strutils]

const URL_ROUTING_JS =
  """;(function(){
if(process.platform!=="linux")return;
try{
var _shell=require("electron").shell;
var _fs=require("fs"),_path=require("path");
var _origOpen=_shell.openExternal;
if(typeof _origOpen!=="function")return;
// Use the literal "default" as the marker suffix when no profile is set,
// so the default profile's callbacks beat any stale named-profile markers
// left over from earlier sessions. The launcher special-cases "default"
// and skips the re-exec.
var _profile=process.env.CLAUDE_PROFILE||"default";
var _runtimeDir=process.env.XDG_RUNTIME_DIR||("/run/user/"+process.getuid());
var _markerPath=_path.join(_runtimeDir,"claude-desktop-pending-auth-"+_profile);
var _authRe=/(?:^|[/?&#])(?:oauth|sso|auth|login|signin|callback|accounts)(?:[/?&#=]|$)/i;
_shell.openExternal=function(url,opts){
try{
if(typeof url==="string"&&_authRe.test(url)){
_fs.writeFileSync(_markerPath,String(Date.now()),{mode:0o600});
console.log("[claude-profile-route] auth marker written for profile '"+_profile+"' (url matched)");
}
}catch(e){console.warn("[claude-profile-route] marker write failed: "+e.message)}
return _origOpen.call(_shell,url,opts);
};
console.log("[claude-profile-route] shell.openExternal hooked for profile '"+_profile+"'");
}catch(e){console.warn("[claude-profile-route] init failed: "+e.message)}
})();"""

const MARKER = "[claude-profile-route]"

proc apply*(input: string): string =
  result = input

  if MARKER in result:
    echo "  [INFO] URL routing hook already applied"
    echo "  [PASS] No changes needed (already patched)"
    return

  let strictPrefix = "\"use strict\";"
  if result.startsWith(strictPrefix):
    result = strictPrefix & URL_ROUTING_JS & result[strictPrefix.len .. ^1]
    echo "  [OK] URL routing hook inserted after \"use strict\""
  else:
    result = URL_ROUTING_JS & result
    echo "  [OK] URL routing hook prepended"

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_profile_url_routing <path_to_index.js>"
    quit(1)

  let filePath = paramStr(1)
  echo "=== Patch: fix_profile_url_routing ==="
  echo "  Target: " & filePath

  if not fileExists(filePath):
    echo "  [FAIL] File not found: " & filePath
    quit(1)

  let input = readFile(filePath)
  let output = apply(input)

  if output != input:
    writeFile(filePath, output)
    echo "  [PASS] Profile URL routing hook installed"
  # If unchanged, apply() already printed a [PASS] for the already-applied case.
