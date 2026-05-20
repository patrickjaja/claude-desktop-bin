# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
# Enable Chrome browser tools ("Claude in Chrome") on Linux.
# Five patches:
#   A - Binary path resolution (native host executable)
#   B - NativeMessagingHosts directory paths
#   C - Chrome user data directory detection (extension/profile discovery)
#   D - Chrome extension auto-install (External Extensions pref)
#   E - Chrome DevTools opener (chrome://inspect via xdg-open)

import std/[os, strformat, strutils]
import regex

const EXPECTED_PATCHES = 5

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

  # Patch A: Binary path resolution
  let alreadyA =
    re2"process\.platform===""linux""\)return require\(""path""\)\.join\(require\(""os""\)\.homedir\(\),"".claude"""
  var alreadyAFound = false
  for m in result.findAll(alreadyA):
    alreadyAFound = true
    break

  if alreadyAFound:
    echo "  [OK] Binary path resolution: already patched (skipped)"
    patchesApplied += 1
  else:
    let patternA = re2"""\"Helpers\",[\w$]+\)}else return [\w$]+\.join\("""

    let linuxBinary =
      "\"linux\")return require(\"path\").join(require(\"os\").homedir(),\".claude\",\"chrome\",\"chrome-native-host\");"

    var countA = result.replaceFirst(
      patternA,
      proc(m: RegexMatch2, s: string): string =
        let matched = s[m.boundaries.a .. m.boundaries.b]
        matched.replace(
          "}else return", "}else if(process.platform===" & linuxBinary & "else return"
        ),
    )
    if countA >= 1:
      echo &"  [OK] Binary path resolution: redirected to Claude Code native host ({countA} match)"
      patchesApplied += 1
    else:
      echo "  [FAIL] Binary path resolution: pattern not found"
      echo "         Debug: rg -o '\"Helpers\".{0,50}' index.js"

  # Patch B: NativeMessagingHosts directory paths
  let linuxPaths =
    ":process.platform===\"linux\"?(()=>{" &
    "const h=require(\"os\").homedir(),p=require(\"path\"),fs=require(\"fs\");" &
    "const dirs=[" &
    "{name:\"Chrome\",path:p.join(h,\".config\",\"google-chrome\",\"NativeMessagingHosts\")}," &
    "{name:\"Chromium\",path:p.join(h,\".config\",\"chromium\",\"NativeMessagingHosts\")}," &
    "{name:\"Brave\",path:p.join(h,\".config\",\"BraveSoftware\",\"Brave-Browser\",\"NativeMessagingHosts\")}," &
    "{name:\"Edge\",path:p.join(h,\".config\",\"microsoft-edge\",\"NativeMessagingHosts\")}," &
    "{name:\"Vivaldi\",path:p.join(h,\".config\",\"vivaldi\",\"NativeMessagingHosts\")}," &
    "{name:\"Opera\",path:p.join(h,\".config\",\"opera\",\"NativeMessagingHosts\")}" &
    "];" & "const nh=p.join(h,\".claude\",\"chrome\",\"chrome-native-host\");" &
    "const nhOk=fs.existsSync(nh);" &
    "const detected=dirs.filter(d=>{try{const pp=p.dirname(d.path);return fs.existsSync(pp)}catch(e){return false}}).map(d=>d.name);" &
    "console.log(\"[browser-tools] diagnostics: native-host=\"+(nhOk?\"found\":\"MISSING (install claude-code CLI)\")+\" browsers=[\"+detected.join(\", \")+\"]\");" &
    "return dirs" & "})():[]"

  let alreadyB = re2"""\"ChromeNativeHost\"\)\}\]:process\.platform===""linux""""
  var alreadyBFound = false
  for m in result.findAll(alreadyB):
    alreadyBFound = true
    break

  if alreadyBFound:
    echo "  [OK] NativeMessagingHosts paths: already patched (skipped)"
    patchesApplied += 1
  else:
    let patternB = re2"""(\"ChromeNativeHost\"\)\}\]):\[\]"""

    var countB = result.replaceFirst(
      patternB,
      proc(m: RegexMatch2, s: string): string =
        s[m.group(0)] & linuxPaths,
    )
    if countB >= 1:
      echo &"  [OK] NativeMessagingHosts paths: added 6 Linux browsers ({countB} match)"
      patchesApplied += 1
    else:
      echo "  [FAIL] NativeMessagingHosts paths: pattern not found"
      echo "         Debug: rg -o '\"ChromeNativeHost\".{0,30}' index.js"

  # Patch C: Chrome user data directory detection (O2A)
  # The O2A function returns Chrome/Edge user data dirs for darwin/win32 but returns [] on Linux.
  # This breaks extension detection and file watching. Add Linux browser paths.
  let alreadyC =
    re2"""process\.platform==="linux"\)\{const A=require\("os"\)\.homedir\(\);return\["""
  var alreadyCFound = false
  for m in result.findAll(alreadyC):
    alreadyCFound = true
    break

  if alreadyCFound:
    echo "  [OK] Chrome user data dirs: already patched (skipped)"
    patchesApplied += 1
  else:
    let patternC = re2"""("User Data"\)\}\]\})(return\[\])"""

    let linuxUserDataDirs =
      "if(process.platform===\"linux\"){" & "const A=require(\"os\").homedir();" &
      "return[" &
      "{name:\"Chrome\",path:require(\"path\").join(A,\".config\",\"google-chrome\")}," &
      "{name:\"Chromium\",path:require(\"path\").join(A,\".config\",\"chromium\")}," &
      "{name:\"Brave\",path:require(\"path\").join(A,\".config\",\"BraveSoftware\",\"Brave-Browser\")}," &
      "{name:\"Vivaldi\",path:require(\"path\").join(A,\".config\",\"vivaldi\")}," &
      "{name:\"Opera\",path:require(\"path\").join(A,\".config\",\"opera\")}" & "]}"

    var countC = result.replaceFirst(
      patternC,
      proc(m: RegexMatch2, s: string): string =
        s[m.group(0)] & linuxUserDataDirs & s[m.group(1)],
    )
    if countC >= 1:
      echo &"  [OK] Chrome user data dirs: added 5 Linux browsers ({countC} match)"
      patchesApplied += 1
    else:
      echo "  [FAIL] Chrome user data dirs: pattern not found"
      echo "         Debug: rg -o '\"User Data\".{{0,30}}return' index.js"

  # Patch D: Chrome extension auto-install (vkr)
  # The vkr function returns an error on non-darwin. On Linux, the Chrome External Extensions
  # directory is at ~/.config/google-chrome/External Extensions/ (and chromium equivalent).
  # Patch: allow linux through the guard, inject Linux-specific install path.
  let alreadyD =
    re2"""process\.platform!=="darwin"&&process\.platform!=="linux"\)return\{status:"""
  var alreadyDFound = false
  for m in result.findAll(alreadyD):
    alreadyDFound = true
    break

  if alreadyDFound:
    echo "  [OK] Chrome extension install: already patched (skipped)"
    patchesApplied += 1
  else:
    # Match the guard clause: if(process.platform!=="darwin")return{status:<enum>.Error,error:`Unsupported platform...`}
    # We need to capture the status enum variable name and the full guard
    let patternD =
      re2"""(if\(process\.platform!=="darwin"\)return\{status:)([\w$]+)(\.Error,error:`Unsupported platform: \$\{process\.platform\}\. Only macOS is supported\.`\})"""

    var countD = result.replaceFirst(
      patternD,
      proc(m: RegexMatch2, s: string): string =
        let enumVar = s[m.group(1)]
        # New guard: reject platforms that are neither darwin nor linux
        "if(process.platform!==\"darwin\"&&process.platform!==\"linux\")return{status:" &
          enumVar &
          ".Error,error:`Unsupported platform: ${process.platform}. Only macOS and Linux are supported.`};" &
          # Linux-specific code path (runs and returns before darwin code)
          "if(process.platform===\"linux\"){" &
          "try{const _h=require(\"os\").homedir(),_p=require(\"path\")," &
          "_id=\"fcoeoabgfenejglbffodgkkbkcdhcgfn\"," &
          "_url=\"https://clients2.google.com/service/update2/crx\"," &
          "_dirs=[_p.join(_h,\".config\",\"google-chrome\"),_p.join(_h,\".config\",\"chromium\")];" &
          "let _ok=!1;for(const _d of _dirs){try{const _e=_p.join(_d,\"External Extensions\");" &
          "require(\"fs\").mkdirSync(_e,{recursive:!0});" &
          "require(\"fs\").writeFileSync(_p.join(_e,_id+\".json\")," &
          "JSON.stringify({external_update_url:_url},null,2),\"utf-8\");" &
          "console.log(\"[Chrome Extension Install] Wrote to \"+_e);_ok=!0}catch(_x){}}" &
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

  # Patch E: Chrome DevTools opening (YOr)
  # The YOr function opens chrome://inspect on darwin/win32 but has no Linux handler.
  # On Linux, use xdg-open which works across all desktop environments.
  let alreadyE =
    re2"""process\.platform==="linux"&&await [\w$]+\("xdg-open",\["chrome://inspect"\]\)"""
  var alreadyEFound = false
  for m in result.findAll(alreadyE):
    alreadyEFound = true
    break

  if alreadyEFound:
    echo "  [OK] Chrome DevTools opener: already patched (skipped)"
    patchesApplied += 1
  else:
    # Match: process.platform==="win32"&&await <execFn>("start",["chrome","chrome://inspect"])
    # Replace with: adding a linux handler after the win32 one
    let patternE =
      re2"""(process\.platform==="win32"&&await )([\w$]+)(\("start",\["chrome","chrome://inspect"\]\))"""

    var countE = result.replaceFirst(
      patternE,
      proc(m: RegexMatch2, s: string): string =
        let execFn = s[m.group(1)]
        # Change win32's && to ? so we can chain :linux&&... as the false branch
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
