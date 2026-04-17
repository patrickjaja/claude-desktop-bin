# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
# Nim port of enable_local_agent_mode.py — backrefs, uses std/nre.
# Also patches mainView.js (sibling of index.js).

import std/[os, strformat, strutils, options]
import std/nre

proc applyIndex(content0: string): string

proc applyMainView(content0: string): string

proc apply*(input: string): string =
  result = applyIndex(input)

proc applyIndex(content0: string): string =
  var content = content0
  let originalContent = content0
  var failed = false

  # Patch 1: Remove platform!=="darwin" gate from chillingSlothFeat/quietPenguin
  let pat1 = re"""(function )([\w$]+)(\(\)\{return )process\.platform!=="darwin"\?\{status:"unavailable"\}:(\{status:"supported"\}\})"""
  var matches: seq[RegexMatch] = @[]
  for m in content.findIter(pat1):
    matches.add(m)
  if matches.len >= 2:
    # Reverse order
    for i in countdown(matches.high, 0):
      let m = matches[i]
      let replacement = m.captures[0] & m.captures[1] & m.captures[2] & m.captures[3]
      let s = m.matchBounds
      content = content[0 ..< s.a] & replacement & content[s.b + 1 .. ^1]
    echo &"  [OK] chillingSlothFeat ({matches[0].captures[1]}) + quietPenguin ({matches[1].captures[1]}): both patched"
  elif matches.len == 1:
    let m = matches[0]
    let replacement = m.captures[0] & m.captures[1] & m.captures[2] & m.captures[3]
    let s = m.matchBounds
    content = content[0 ..< s.a] & replacement & content[s.b + 1 .. ^1]
    echo &"  [OK] darwin-gated function ({matches[0].captures[1]}): 1 match"
  else:
    echo "  [FAIL] darwin-gated functions: 0 matches, expected at least 1"
    failed = true

  if failed:
    echo "  [FAIL] Required patterns did not match"
    raise newException(ValueError, "enable_local_agent_mode: patch 1 failed")

  # Patch 1b: Bypass yukonSilver (NH) platform gate on Linux
  let nhPatOld = re"""(function [\w$]+\(\)\{)(const ([\w$]+)=process\.platform;if\(\3!=="darwin"&&\3!=="win32"\)return\{status:"unsupported",reason:`Unsupported platform: \$\{\3\}`\})"""
  let nhPatNew = re"""(function [\w$]+\(\)\{)(const ([\w$]+)=process\.platform;if\(\3!=="darwin"&&\3!=="win32"\)return\{status:"unsupported",reason:[\w$]+\.formatMessage\(\{defaultMessage:"Cowork is not currently supported on \{platform\}"(?:,id:"[^"]*")?\},\{platform:[\w$]+\(\)\}\),unsupportedCode:"unsupported_platform"\};)"""

  var count1b = 0
  # Try old pattern first with count=1
  let mOld = content.find(nhPatOld)
  if mOld.isSome:
    let mm = mOld.get
    let replacement = mm.captures[0] & "if(process.platform===\"linux\")return{status:\"supported\"};" & mm.captures[1]
    let s = mm.matchBounds
    content = content[0 ..< s.a] & replacement & content[s.b + 1 .. ^1]
    count1b = 1

  if count1b >= 1:
    echo &"  [OK] yukonSilver (NH): Linux early return injected ({count1b} match)"
  elif content.contains("if(process.platform===\"linux\")return{status:\"supported\"};const"):
    echo "  [OK] yukonSilver (NH): already patched"
  else:
    let mNew = content.find(nhPatNew)
    if mNew.isSome:
      let mm = mNew.get
      let replacement = mm.captures[0] & "if(process.platform===\"linux\")return{status:\"supported\"};" & mm.captures[1]
      let s = mm.matchBounds
      content = content[0 ..< s.a] & replacement & content[s.b + 1 .. ^1]
      count1b = 1
      echo &"  [OK] yukonSilver (NH): Linux early return injected (formatMessage variant, {count1b} match)"
    else:
      echo "  [WARN] yukonSilver (NH): 0 matches"

  # Patch 2
  echo "  [OK] chillingSlothLocal: no gate needed (naturally returns supported on Linux)"

  # Patch 3: Override features in mC() async merger
  let overrides = ",quietPenguin:{status:\"supported\"},louderPenguin:{status:\"supported\"},chillingSlothFeat:{status:\"supported\"},chillingSlothLocal:{status:\"supported\"},yukonSilver:{status:\"supported\"},yukonSilverGems:{status:\"supported\"},ccdPlugins:{status:\"supported\"},computerUse:{status:\"supported\"},coworkKappa:{status:\"supported\"}"

  let pat3New = re"""(return\{\.\.\.([\w$]+)\(\),[^}]+)(\}\};)"""
  var count3 = 0
  let m3 = content.find(pat3New)
  if m3.isSome:
    let mm = m3.get
    let endPos = mm.matchBounds.b + 1  # exclusive end
    let tailLen = "}};".len
    content = content[0 ..< endPos - tailLen] & overrides & "}};" & content[endPos .. ^1]
    count3 = 1

  if count3 >= 1:
    echo &"  [OK] mC() feature merger: 9 features overridden ({count3} match)"
  else:
    # Fallback: old format
    let pat3Old = re"""(const [\w$]+=async\(\)=>\(\{\.\.\.[\w$]+\(\),[^}]+)(await [\w$]+\(\))\}\)"""
    var countOld = 0
    content = content.replace(pat3Old, proc (m: RegexMatch): string =
      inc countOld
      m.captures[0] & m.captures[1] & overrides & "})"
    )
    if countOld >= 1:
      echo &"  [OK] mC() feature merger: 9 features overridden (old format, {countOld} match)"
      count3 = countOld
    else:
      echo "  [FAIL] mC() feature merger: 0 matches, expected 1"
      failed = true

  # Patch 3b: Enable coworkKappa GrowthBook flag (123929380)
  let kappaPat = re"""[\w$]+\("123929380"\)"""
  var kappaApplied = 0
  content = content.replace(kappaPat, proc (m: RegexMatch): string =
    inc kappaApplied
    "!0"
  )
  if kappaApplied >= 3:
    echo &"  [OK] coworkKappa flag 123929380: forced ON ({kappaApplied} matches)"
  elif kappaApplied > 0:
    echo &"  [WARN] coworkKappa flag 123929380: only {kappaApplied}/3 matches (expected 3)"
  else:
    echo "  [FAIL] coworkKappa flag 123929380: 0 matches"
    failed = true

  # Patch 4: Change preferences defaults
  let pat3a = "quietPenguinEnabled:!1,louderPenguinEnabled:!1"
  let repl3a = "quietPenguinEnabled:!0,louderPenguinEnabled:!0"
  var count3a = 0
  while true:
    let idx = content.find(pat3a)
    if idx < 0: break
    content = content[0 ..< idx] & repl3a & content[idx + pat3a.len .. ^1]
    inc count3a
  if count3a >= 1:
    echo &"  [OK] Preferences defaults: quietPenguinEnabled + louderPenguinEnabled → true ({count3a} match)"
  else:
    echo "  [FAIL] Preferences defaults: 0 matches for quietPenguinEnabled/louderPenguinEnabled"
    failed = true

  if failed:
    echo "  [FAIL] Required patterns did not match"
    raise newException(ValueError, "enable_local_agent_mode: failed")

  # Patch 5: HTTP header platform spoof
  let headerPat = re"""(const [\w$]+=[\w$]+\.app\.getVersion\(\),)([\w$]+)(=)([\w$]+)(\.platform,)([\w$]+)(=\4\.getSystemVersion\(\)[;,])"""
  var count5 = 0
  content = content.replace(headerPat, proc (m: RegexMatch): string =
    inc count5
    let platVar = m.captures[1]
    let osMod = m.captures[3]
    let verVar = m.captures[5]
    m.captures[0] & platVar & m.captures[2] & "process.platform===\"linux\"?\"darwin\":" & osMod & m.captures[4] & verVar & m.captures[6]
  )
  if count5 >= 1:
    echo &"  [OK] HTTP header platform spoof: {count5} match(es)"
  else:
    echo "  [FAIL] HTTP header platform spoof: 0 matches"
    raise newException(ValueError, "enable_local_agent_mode: header spoof failed")

  # Patch 5b: Spoof User-Agent
  let uaPat = re"""(let )([\w$]+)(=)([\w$]+)(;)([\w$]+\.set\("user-agent",)\2(\))"""
  var count5b = 0
  content = content.replace(uaPat, proc (m: RegexMatch): string =
    inc count5b
    let vvar = m.captures[1]
    let orig = m.captures[3]
    m.captures[0] & vvar & m.captures[2] & orig & m.captures[4] &
      "if(process.platform===\"linux\"){" & vvar & "=" & vvar & ".replace(/X11; Linux [^)]+/g,\"Macintosh; Intel Mac OS X 10_15_7\")}" &
      m.captures[5] & vvar & m.captures[6]
  )
  if count5b >= 1:
    echo &"  [OK] User-Agent header spoof: {count5b} match(es)"
  else:
    echo "  [FAIL] User-Agent header spoof: 0 matches"
    raise newException(ValueError, "enable_local_agent_mode: UA spoof failed")

  # Patch 6: getSystemInfo platform spoof
  let sysinfoPat = re"""(platform:)process\.platform(,arch:process\.arch,total_memory:[\w$]+\.totalmem\(\))"""
  var count6 = 0
  content = content.replace(sysinfoPat, proc (m: RegexMatch): string =
    inc count6
    m.captures[0] & "(process.platform===\"linux\"?\"win32\":process.platform)" & m.captures[1]
  )
  if count6 >= 1:
    echo &"  [OK] getSystemInfo platform spoof: {count6} match(es)"
  else:
    echo "  [FAIL] getSystemInfo platform spoof: 0 matches"
    raise newException(ValueError, "enable_local_agent_mode: sysinfo spoof failed")

  if content != originalContent:
    echo "  [PASS] Code + Cowork features enabled in index.js"
  else:
    echo "  [WARN] No changes made to index.js (patterns may have already been applied)"

  # Patch 8: navigator spoof
  let navigatorMarker = "__nav_spoof_applied"
  if content.contains(navigatorMarker):
    echo "  [OK] navigator spoof: already applied"
  else:
    let navSpoofJs =
      "if(process.platform===\"linux\"){" &
      "const __nav_spoof_applied=!0;" &
      "const __oUA=require(\"electron\").app.userAgentFallback||\"\";" &
      "require(\"electron\").app.userAgentFallback=" &
      "__oUA.replace(/X11; Linux [^)]+/g,\"Windows NT 10.0; Win64; x64\");" &
      "const __navJS=\"try{Object.defineProperty(navigator,\\\"platform\\\",{get:()=>\\\"Win32\\\",configurable:!0})}catch(e){}\";" &
      "require(\"electron\").app.on(\"web-contents-created\",(ev,wc)=>{" &
      "wc.on(\"did-navigate\",()=>{wc.executeJavaScript(__navJS).catch(()=>{})});" &
      "wc.on(\"dom-ready\",()=>{wc.executeJavaScript(__navJS).catch(()=>{})})" &
      "})" &
      "}"
    let strictPrefix = "\"use strict\";"
    if content.startsWith(strictPrefix):
      content = strictPrefix & navSpoofJs & content[strictPrefix.len .. ^1]
      echo "  [OK] navigator spoof: injected in index.js (userAgent + platform)"
    else:
      echo "  [WARN] navigator spoof: could not find 'use strict' prefix"

  result = content

proc applyMainView(content0: string): string =
  var content = content0
  let mvPat = re"""(Object\.fromEntries\(Object\.entries\(process\)\.filter\(\(\[[\w$]+\]\)=>[\w$]+\[[\w$]+\]\)\);)([\w$]+)(\.version=[\w$]+\(\)\.appVersion;)"""

  var mvCount = 0
  let m = content.find(mvPat)
  if m.isSome:
    let mm = m.get
    let procVar = mm.captures[1]
    let replacement = mm.captures[0] & procVar & mm.captures[2] & "if(process.platform===\"linux\"){" & procVar & ".platform=\"win32\"}"
    let s = mm.matchBounds
    content = content[0 ..< s.a] & replacement & content[s.b + 1 .. ^1]
    mvCount = 1

  if mvCount >= 1:
    echo &"  [OK] mainView.js: window.process.platform spoof ({mvCount} match)"
  elif content.contains(".platform=\"win32\"") or content.contains(".platform=\"darwin\""):
    echo "  [OK] mainView.js: window.process.platform spoof already applied"
  else:
    echo "  [FAIL] mainView.js: window.process.platform spoof: 0 matches"
    raise newException(ValueError, "enable_local_agent_mode: mainView spoof failed")

  if content != content0:
    echo "  [PASS] mainView.js patched successfully"

  result = content

when isMainModule:
  let file = paramStr(1)
  echo "=== Patch: enable_local_agent_mode ==="
  echo &"  Target: {file}"
  let input = readFile(file)
  let output = applyIndex(input)
  if output != input:
    writeFile(file, output)

  # Also patch mainView.js if present (sibling of index.js)
  let mvPath = parentDir(file) / "mainView.js"
  if fileExists(mvPath):
    let mvInput = readFile(mvPath)
    let mvOutput = applyMainView(mvInput)
    if mvOutput != mvInput:
      writeFile(mvPath, mvOutput)
  else:
    echo &"  [WARN] mainView.js not found at {mvPath}"
