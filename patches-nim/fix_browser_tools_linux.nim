# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
# Nim port of fix_browser_tools_linux.py

import std/[os, strformat, strutils]
import regex

proc apply*(input: string): string =
  var content = input
  let original = input
  var patchesApplied = 0

  # ── Patch A: Binary path resolution ───────────────────────────────
  let patternA = re2""""Helpers",[\w$]+\)\}else return [\w$]+\.join\("""
  const LINUX_BINARY = "\"linux\")return require(\"path\").join(require(\"os\").homedir(),\".claude\",\"chrome\",\"chrome-native-host\");"
  let alreadyA = re2"""process\.platform==="linux"\)return require\("path"\)\.join\(require\("os"\)\.homedir\(\),"\.claude""""
  var mA: RegexMatch2
  if content.find(alreadyA, mA):
    echo "  [OK] Binary path resolution: already patched (skipped)"
    patchesApplied += 1
  else:
    var countA = 0
    var found = false
    # Python uses count=1 — only replace first
    content = content.replace(patternA, proc (m: RegexMatch2, s: string): string =
      if found: return s[m.boundaries]
      found = true
      inc countA
      let matched = s[m.boundaries]
      matched.replace("}else return",
        "}else if(process.platform===" & LINUX_BINARY & "else return")
    )
    if countA >= 1:
      echo &"  [OK] Binary path resolution: redirected to Claude Code native host ({countA} match)"
      patchesApplied += 1
    else:
      echo "  [FAIL] Binary path resolution: pattern not found"
      echo "         Debug: rg -o '\"Helpers\".{0,50}' index.js"

  # ── Patch B: NativeMessagingHosts directory paths ─────────────────
  const LINUX_PATHS =
    ":process.platform===\"linux\"?(()=>{" &
    "const h=require(\"os\").homedir(),p=require(\"path\"),fs=require(\"fs\");" &
    "const dirs=[" &
    "{name:\"Chrome\",path:p.join(h,\".config\",\"google-chrome\",\"NativeMessagingHosts\")}," &
    "{name:\"Chromium\",path:p.join(h,\".config\",\"chromium\",\"NativeMessagingHosts\")}," &
    "{name:\"Brave\",path:p.join(h,\".config\",\"BraveSoftware\",\"Brave-Browser\",\"NativeMessagingHosts\")}," &
    "{name:\"Edge\",path:p.join(h,\".config\",\"microsoft-edge\",\"NativeMessagingHosts\")}," &
    "{name:\"Vivaldi\",path:p.join(h,\".config\",\"vivaldi\",\"NativeMessagingHosts\")}," &
    "{name:\"Opera\",path:p.join(h,\".config\",\"opera\",\"NativeMessagingHosts\")}" &
    "];" &
    "const nh=p.join(h,\".claude\",\"chrome\",\"chrome-native-host\");" &
    "const nhOk=fs.existsSync(nh);" &
    "const detected=dirs.filter(d=>{try{const pp=p.dirname(d.path);return fs.existsSync(pp)}catch(e){return false}}).map(d=>d.name);" &
    "console.log(\"[browser-tools] diagnostics: native-host=\"+(nhOk?\"found\":\"MISSING (install claude-code CLI)\")+\" browsers=[\"+detected.join(\", \")+\"]\");" &
    "return dirs" &
    "})():[]"

  let patternB = re2("(\"ChromeNativeHost\"\\)\\}\\]):\\[\\]")
  let alreadyB = re2("\"ChromeNativeHost\"\\)\\}\\]:process\\.platform===\"linux\"")
  var mB: RegexMatch2
  if content.find(alreadyB, mB):
    echo "  [OK] NativeMessagingHosts paths: already patched (skipped)"
    patchesApplied += 1
  else:
    var countB = 0
    var found = false
    content = content.replace(patternB, proc (m: RegexMatch2, s: string): string =
      if found: return s[m.boundaries]
      found = true
      inc countB
      s[m.group(0)] & LINUX_PATHS
    )
    if countB >= 1:
      echo &"  [OK] NativeMessagingHosts paths: added 6 Linux browsers ({countB} match)"
      patchesApplied += 1
    else:
      echo "  [FAIL] NativeMessagingHosts paths: pattern not found"
      echo "         Debug: rg -o '\"ChromeNativeHost\".{0,30}' index.js"

  const EXPECTED = 2
  if patchesApplied < EXPECTED:
    echo &"  [FAIL] Only {patchesApplied}/{EXPECTED} patches applied — check [WARN]/[FAIL] messages above"
    raise newException(ValueError, &"fix_browser_tools_linux: only {patchesApplied}/{EXPECTED} applied")

  if content == original:
    echo &"  [OK] All {patchesApplied} patches already applied (no changes needed)"
    return original

  # Verify brace balance
  let origDelta = original.count('{') - original.count('}')
  let newDelta = content.count('{') - content.count('}')
  if origDelta != newDelta:
    let diff = newDelta - origDelta
    echo &"  [FAIL] Patch introduced brace imbalance: {diff:+d} unmatched braces"
    raise newException(ValueError, &"fix_browser_tools_linux: brace imbalance {diff}")

  result = content

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_browser_tools_linux <file>"
    quit(1)
  let file = paramStr(1)
  echo "=== Patch: fix_browser_tools_linux ==="
  echo &"  Target: {file}"
  let input = readFile(file)
  let output = apply(input)
  if output != input:
    writeFile(file, output)
    echo &"  [PASS] patches applied"
  else:
    echo "  [OK] No changes needed"
