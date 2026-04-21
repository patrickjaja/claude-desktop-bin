# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
#
# Fix Cowork tab not applying the user's chat font preference on load.
#
# The claude.ai SPA lazy-initializes font preferences when the Chat view
# mounts. If Cowork is visited first, font-claude-response-body resolves
# to the default Serif. This patch injects a script on dom-ready that
# reads the font preference from localStorage and applies matching CSS,
# ensuring both Chat and Cowork have the correct font from startup.
#
# Break risk: VERY LOW — Same "use strict;" anchor as custom_themes.
# Uses only standard DOM APIs. No regex on minified app code.

import std/[os, strutils]

const FIX_JS = staticRead("../js/fix_cowork_font.js")

proc escapeJs(s: string): string =
  result = s
  result = result.replace("\\", "\\\\")
  result = result.replace("\"", "\\\"")
  result = result.replace("\n", "\\n")
  result = result.replace("\r", "")

const INJECTION = """;(function(){
if(typeof process==="undefined"||!process.versions||!process.versions.electron)return;
var _app=require("electron").app;
var __cwf_js="""" & escapeJs(FIX_JS) & """";
_app.on("web-contents-created",function(_ev,wc){
wc.on("dom-ready",function(){
try{
var url=wc.getURL()||"";
if(url.indexOf("claude.ai")!==-1||url.indexOf("claude.com")!==-1){
wc.executeJavaScript(__cwf_js).catch(function(){});
}
}catch(e){}
});
});
})();"""

proc apply*(input: string): string =
  result = input

  let marker = "__cwf_js"
  if marker in result:
    echo "  [OK] Cowork font fix: already patched (skipped)"
    return

  let strictPrefix = "\"use strict\";"
  if result.startsWith(strictPrefix):
    result = strictPrefix & INJECTION & result[strictPrefix.len .. ^1]
    echo "  [OK] Cowork font fix injected after \"use strict\""
  else:
    result = INJECTION & result
    echo "  [OK] Cowork font fix prepended"

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_cowork_font <path_to_index.js>"
    quit(1)
  let filePath = paramStr(1)
  echo "=== Patch: fix_cowork_font ==="
  echo "  Target: " & filePath
  if not fileExists(filePath):
    echo "  [FAIL] File not found: " & filePath
    quit(1)
  let input = readFile(filePath)
  let output = apply(input)
  if output != input:
    writeFile(filePath, output)
    echo "  [PASS] Cowork font fix applied"
  else:
    echo "  [WARN] No changes made"
