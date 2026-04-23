# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
# Enable Chrome browser tools ("Claude in Chrome") on Linux.
# Two patches: binary path resolution and NativeMessagingHosts directory paths.

import std/[os, strformat, strutils]
import regex

const EXPECTED_PATCHES = 2

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
