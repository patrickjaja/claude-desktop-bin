# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
# Enable Chrome browser tools ("Claude in Chrome") on Linux.
#
# State on the official Linux .deb (verified 2026-06): browser-tools is PARTIALLY
# upstreamed. The browser directory enumerator is now native and Linux-shaped:
#     function O_i(){const A=process.env.XDG_CONFIG_HOME;return A&&j.isAbsolute(A)?A:j.join(<os>.homedir(),".config")}
#     function xSA(){<os>.homedir();{const A=O_i();return[{name:"Chrome",path:j.join(A,"google-chrome")},
#                                                        {name:"Edge",path:j.join(A,"microsoft-edge")}]}}
#     function Y_i(){return <os>.homedir(),xSA().map(A=>({name:A.name,path:j.join(A.path,"NativeMessagingHosts")}))}
# and upstream's OWN sync loop writes the native-messaging manifest to those dirs:
#     for(const{name:A,path:e}of Y_i())...l2n(e,A)/aer(e,A)...     // install/remove
# plus a profile/extension discovery loop `x_i()` that iterates xSA(). So Chrome +
# Edge work natively on Linux now.
#
# What's left for us — 4 sub-patches:
#   A  Native-host BINARY PATH: redirect to the Claude Code native host under
#      ~/.claude (the bundled artifacts path is Anthropic-internal and absent in
#      our repackage). Anchor refactored from `${X}.exe` to a bare const.
#   BC EXTEND the native browser list: xSA() ships ONLY Chrome+Edge. We add
#      Chromium, Brave, Vivaldi and Opera. Because BOTH the NativeMessagingHosts
#      install loop (via Y_i→xSA) AND profile discovery (x_i→xSA) derive from
#      xSA(), extending this ONE function covers what the old separate Patch B
#      (manifest write loop) and Patch C (user-data dirs) did — and reuses
#      upstream's own manifest writer instead of duplicating it.
#   D  Extension AUTO-INSTALL: still mac-gated (`Only macOS is supported.`). Inject
#      the Linux External-Extensions path.
#   E  DevTools opener: still darwin/win32 only. Add an xdg-open Linux handler.

import std/[os, strformat, strutils]
import regex

const EXPECTED_PATCHES = 4

proc replaceFirst(
    content: var string, pattern: Regex2, subFn: proc(m: RegexMatch2, s: string): string
): int =
  var found = false
  var resultStr = ""
  var lastEnd = 0
  for m in content.findAll(pattern):
    if not found:
      let bounds = m.boundaries
      resultStr &= content[lastEnd ..< bounds.a]
      resultStr &= subFn(m, content)
      lastEnd = bounds.b + 1
      found = true
      break
  if found:
    resultStr &= content[lastEnd .. ^1]
    content = resultStr
    return 1
  return 0

proc apply*(input: string): string =
  result = input
  var patchesApplied = 0

  # ── Patch A: native-host binary path ──────────────────────────────────────
  # New shape: function wbt(){const A=Qbt;return aA.app.isPackaged?
  #   j.join(process.resourcesPath,A):j.join(aA.app.getAppPath(),
  #   "../../packages/desktop/chrome-native-host/artifacts",A)}
  # Inject a Linux short-circuit returning the Claude Code native host under
  # ~/.claude. Anchor on the function head up to "isPackaged?".
  let alreadyA =
    re2"""if\(process\.platform==="linux"\)return require\("path"\)\.join\(require\("os"\)\.homedir\(\),"\.claude","chrome","chrome-native-host"\)"""
  var amA: RegexMatch2
  if result.find(alreadyA, amA):
    echo "  [OK] Binary path resolution: already patched (skipped)"
    patchesApplied += 1
  else:
    # function NAME(){const VAR=VAR2;return ELECTRON.app.isPackaged?
    # (VAR2 is now a bare const, no `${...}.exe` template). Require the
    # chrome-native-host artifacts path on the false branch to avoid matching an
    # unrelated isPackaged fn.
    let patternA =
      re2"""(function [\w$]+\(\)\{)(const [\w$]+=[\w$]+;return [\w$]+\.app\.isPackaged\?[\w$]+\.join\(process\.resourcesPath,[\w$]+\):[\w$]+\.join\([\w$]+\.app\.getAppPath\(\),"\.\./\.\./packages/desktop/chrome-native-host/artifacts",)"""
    let linuxBinary =
      "if(process.platform===\"linux\")return require(\"path\").join(require(\"os\").homedir(),\".claude\",\"chrome\",\"chrome-native-host\");"
    var countA = result.replaceFirst(
      patternA,
      proc(m: RegexMatch2, s: string): string =
        s[m.group(0)] & linuxBinary & s[m.group(1)],
    )
    if countA >= 1:
      echo &"  [OK] Binary path resolution: redirected to Claude Code native host ({countA} match)"
      patchesApplied += 1
    else:
      echo "  [FAIL] Binary path resolution: pattern not found (wbt() shape changed?)"
      echo "         Debug: rg -o 'chrome-native-host/artifacts' index.js"

  # ── Patch BC: extend native browser list (xSA) to 6 browsers ──────────────
  # Native xSA() returns ONLY Chrome+Edge. Replace its return array with one that
  # also includes Chromium/Brave/Vivaldi/Opera, reusing the upstream config-dir
  # var (the result of O_i(), bound to `const <A>=`). Both the NativeMessagingHosts
  # install loop (Y_i→xSA) and profile discovery (x_i→xSA) then cover all 6.
  let alreadyBC = re2"""\{name:"Chromium",path:[\w$]+\.join\([\w$]+,"chromium"\)\}"""
  var amBC: RegexMatch2
  if result.find(alreadyBC, amBC):
    echo "  [OK] Browser list (xSA): already extended to Chromium/Brave/Vivaldi/Opera (skipped)"
    patchesApplied += 1
  else:
    # function xSA(){<os>.homedir();{const <CFG>=O_i();return[{name:"Chrome",...},{name:"Edge",...}]}}
    # Capture g0 = head through `const <CFG>=<dirfn>();return[`, g1 = the config-dir
    # var name, then we rebuild the full 6-entry array and keep the original
    # Chrome+Edge entries.
    let patternBC =
      re2"""(function [\w$]+\(\)\{[\w$]+\.homedir\(\);\{const )([\w$]+)(=[\w$]+\(\);return\[)(\{name:"Chrome",path:([\w$]+)\.join\([\w$]+,"google-chrome"\)\},\{name:"Edge",path:[\w$]+\.join\([\w$]+,"microsoft-edge"\)\})(\])"""
    var countBC = result.replaceFirst(
      patternBC,
      proc(m: RegexMatch2, s: string): string =
        let head = s[m.group(0)] # "function …{<os>.homedir();{const "
        let cfgVar = s[m.group(1)] # the O_i() result var
        let mid = s[m.group(2)] # "=O_i();return["
        let chromeEdge = s[m.group(3)] # original Chrome+Edge entries
        let joinVar = s[m.group(4)] # the path module var used in `<j>.join`
        let extra =
          ",{name:\"Chromium\",path:" & joinVar & ".join(" & cfgVar & ",\"chromium\")}" &
          ",{name:\"Brave\",path:" & joinVar & ".join(" & cfgVar &
          ",\"BraveSoftware\",\"Brave-Browser\")}" & ",{name:\"Vivaldi\",path:" & joinVar &
          ".join(" & cfgVar & ",\"vivaldi\")}" & ",{name:\"Opera\",path:" & joinVar &
          ".join(" & cfgVar & ",\"opera\")}"
        head & cfgVar & mid & chromeEdge & extra & s[m.group(5)],
    )
    if countBC >= 1:
      echo &"  [OK] Browser list (xSA): extended to 6 browsers (Chromium/Brave/Vivaldi/Opera added) ({countBC} match)"
      patchesApplied += 1
    else:
      echo "  [FAIL] Browser list (xSA): native Chrome+Edge enumerator not found"
      echo "         Debug: rg -o 'name:\"Chrome\",path:[\\w$]+.join([\\w$]+,\"google-chrome\")' index.js"

  # ── Patch D: Chrome extension auto-install (still mac-gated) ───────────────
  let alreadyD =
    re2"""process\.platform!=="darwin"&&process\.platform!=="linux"\)return\{status:"""
  var amD: RegexMatch2
  if result.find(alreadyD, amD):
    echo "  [OK] Chrome extension install: already patched (skipped)"
    patchesApplied += 1
  else:
    let patternD =
      re2"""(if\(process\.platform!=="darwin"\)return\{status:)([\w$]+)(\.Error,error:`Unsupported platform: \$\{process\.platform\}\. Only macOS is supported\.`\})"""
    var countD = result.replaceFirst(
      patternD,
      proc(m: RegexMatch2, s: string): string =
        let enumVar = s[m.group(1)]
        "if(process.platform!==\"darwin\"&&process.platform!==\"linux\")return{status:" &
          enumVar &
          ".Error,error:`Unsupported platform: ${process.platform}. Only macOS and Linux are supported.`};" &
          "if(process.platform===\"linux\"){" &
          "try{const _h=require(\"os\").homedir(),_p=require(\"path\")," &
          "_id=\"fcoeoabgfenejglbffodgkkbkcdhcgfn\"," &
          "_url=\"https://clients2.google.com/service/update2/crx\"," &
          "_dirs=[_p.join(_h,\".config\",\"google-chrome\"),_p.join(_h,\".config\",\"chromium\")];" &
          "let _ok=!1;for(const _d of _dirs){try{const _e=_p.join(_d,\"External Extensions\");" &
          "require(\"fs\").mkdirSync(_e,{recursive:!0});" &
          "require(\"fs\").writeFileSync(_p.join(_e,_id+\".json\")," &
          "JSON.stringify({external_update_url:_url},null,2),\"utf-8\");" &
          "(globalThis.__cdbDiag||console.log)(\"[Chrome Extension Install] Wrote to \"+_e);_ok=!0}catch(_x){}}" &
          "return _ok?{status:" & enumVar & ".Succeeded}:{status:" & enumVar &
          ".Error,error:\"No Chrome/Chromium config dirs found on Linux\"}}" &
          "catch(e){return{status:" & enumVar &
          ".Error,error:e instanceof Error?e.message:\"Unknown error\"}}}",
    )
    if countD >= 1:
      echo &"  [OK] Chrome extension install: added Linux support ({countD} match)"
      patchesApplied += 1
    else:
      echo "  [FAIL] Chrome extension install: pattern not found"
      echo "         Debug: rg -o 'Only macOS is supported.{{0,20}}' index.js"

  # ── Patch E: Chrome DevTools opener (still darwin/win32 only) ──────────────
  let alreadyE =
    re2"""process\.platform==="linux"&&await [\w$]+\("xdg-open",\["chrome://inspect"\]\)"""
  var amE: RegexMatch2
  if result.find(alreadyE, amE):
    echo "  [OK] Chrome DevTools opener: already patched (skipped)"
    patchesApplied += 1
  else:
    let patternE =
      re2"""(process\.platform==="win32"&&await )([\w$]+)(\("start",\["chrome","chrome://inspect"\]\))"""
    var countE = result.replaceFirst(
      patternE,
      proc(m: RegexMatch2, s: string): string =
        let execFn = s[m.group(1)]
        "process.platform===\"win32\"?await " & execFn & s[m.group(2)] &
          ":process.platform===\"linux\"&&await " & execFn &
          "(\"xdg-open\",[\"chrome://inspect\"])",
    )
    if countE >= 1:
      echo &"  [OK] Chrome DevTools opener: added Linux xdg-open handler ({countE} match)"
      patchesApplied += 1
    else:
      echo "  [FAIL] Chrome DevTools opener: pattern not found"
      echo "         Debug: rg -o 'chrome://inspect.{{0,30}}' index.js"

  if patchesApplied < EXPECTED_PATCHES:
    raise newException(
      ValueError,
      &"fix_browser_tools_linux: Only {patchesApplied}/{EXPECTED_PATCHES} patches applied",
    )

  # Verify brace balance
  let originalDelta = input.count('{') - input.count('}')
  let patchedDelta = result.count('{') - result.count('}')
  if originalDelta != patchedDelta:
    let diff = patchedDelta - originalDelta
    raise newException(
      ValueError,
      &"fix_browser_tools_linux: Patch introduced brace imbalance: {diff:+} unmatched braces",
    )

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_browser_tools_linux <file>"
    quit(1)
  let file = paramStr(1)
  echo "=== Patch: fix_browser_tools_linux ==="
  echo &"  Target: {file}"
  if not fileExists(file):
    echo &"  [FAIL] File not found: {file}"
    quit(1)
  let input = readFile(file)
  let output = apply(input)
  if output == input:
    echo &"  [OK] All patches already applied (no changes needed)"
  else:
    writeFile(file, output)
    echo &"  [PASS] Patches applied"
