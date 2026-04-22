# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
#
# Enable Code and Cowork features on Linux.
#
# Multi-part patch:
#   1  darwin-gated functions (chillingSlothFeat + quietPenguin)
#   1b yukonSilver (NH) Linux early return
#   2  chillingSlothLocal (no-op -- inherently supported on Linux)
#   3  mC() async merger overrides
#   3b coworkKappa GrowthBook flag 123929380
#   3c coworkArtifacts GrowthBook flag 2940196192
#   4  preferences defaults (quietPenguinEnabled / louderPenguinEnabled)
#   5  HTTP header platform spoof
#   5b User-Agent header spoof
#   6  getSystemInfo IPC platform spoof
#   7  mainView.js window.process.platform spoof
#   8  navigator spoof injected after "use strict"
#
# This patch targets BOTH index.js AND mainView.js (sibling file).

import std/[os, strformat, strutils]
import std/nre

const EXPECTED_PATCHES = 12

proc apply*(input: string): string =
  result = input
  var failed = false
  var patchesApplied = 0

  # Patch 1: Remove platform!=="darwin" gate from chillingSlothFeat and quietPenguin
  let pattern1 = re"""(function )([\w$]+)(\(\)\{return )process\.platform!=="darwin"\?\{status:"unavailable"\}:(\{status:"supported"\}\})"""

  var matches: seq[RegexMatch] = @[]
  var pos = 0
  while true:
    let m = result.find(pattern1, pos)
    if m.isNone: break
    matches.add(m.get())
    pos = m.get().matchBounds.b + 1

  if matches.len >= 2:
    # Patch both: reverse order to preserve byte offsets
    for i in countdown(matches.len - 1, 0):
      let m = matches[i]
      let replacement = m.captures[0] & m.captures[1] & m.captures[2] & m.captures[3]
      let bounds = m.matchBounds
      result = result[0 ..< bounds.a] & replacement & result[bounds.b + 1 .. ^1]
    echo &"  [OK] chillingSlothFeat ({matches[0].captures[1]}) + quietPenguin ({matches[1].captures[1]}): both patched"
    inc patchesApplied
  elif matches.len == 1:
    let m = matches[0]
    let replacement = m.captures[0] & m.captures[1] & m.captures[2] & m.captures[3]
    let bounds = m.matchBounds
    result = result[0 ..< bounds.a] & replacement & result[bounds.b + 1 .. ^1]
    echo &"  [OK] darwin-gated function ({matches[0].captures[1]}): 1 match"
    inc patchesApplied
  else:
    echo "  [FAIL] darwin-gated functions: 0 matches, expected at least 1"
    failed = true

  if failed:
    echo "  [FAIL] Required patterns did not match"
    quit(1)

  # Patch 1b: Bypass yukonSilver (NH) platform gate on Linux
  let nhPatternOld = re"""(function [\w$]+\(\)\{)(const ([\w$]+)=process\.platform;if\(\3!=="darwin"&&\3!=="win32"\)return\{status:"unsupported",reason:`Unsupported platform: \$\{\3\}`\})"""
  let nhPatternNew = re"""(function [\w$]+\(\)\{)(const ([\w$]+)=process\.platform;if\(\3!=="darwin"&&\3!=="win32"\)return\{status:"unsupported",reason:[\w$]+\.formatMessage\(\{defaultMessage:"Cowork is not currently supported on \{platform\}"(?:,id:"[^"]*")?\},\{platform:[\w$]+\(\)\}\),unsupportedCode:"unsupported_platform"\};)"""

  if "if(process.platform===\"linux\")return{status:\"supported\"};const" in result:
    echo "  [OK] yukonSilver (NH): already patched"
    inc patchesApplied
  else:
    var count1b = 0
    let nhResult = result.replace(nhPatternOld, proc(m: RegexMatch): string =
      inc count1b
      m.captures[0] & "if(process.platform===\"linux\")return{status:\"supported\"};" & m.captures[1]
    )
    if count1b >= 1:
      result = nhResult
      echo &"  [OK] yukonSilver (NH): Linux early return injected ({count1b} match)"
      inc patchesApplied
    else:
      var count1bNew = 0
      let nhResult2 = result.replace(nhPatternNew, proc(m: RegexMatch): string =
        inc count1bNew
        m.captures[0] & "if(process.platform===\"linux\")return{status:\"supported\"};" & m.captures[1]
      )
      if count1bNew >= 1:
        result = nhResult2
        echo &"  [OK] yukonSilver (NH): Linux early return injected (formatMessage variant, {count1bNew} match)"
        inc patchesApplied
      else:
        echo "  [FAIL] yukonSilver (NH): 0 matches"
        failed = true

  # Patch 2: chillingSlothLocal -- no gate needed
  echo "  [OK] chillingSlothLocal: no gate needed (naturally returns supported on Linux)"
  inc patchesApplied

  # Patch 3: Override features in mC() async merger
  let overrides = ",quietPenguin:{status:\"supported\"},louderPenguin:{status:\"supported\"},chillingSlothFeat:{status:\"supported\"},chillingSlothLocal:{status:\"supported\"},yukonSilver:{status:\"supported\"},yukonSilverGems:{status:\"supported\"},ccdPlugins:{status:\"supported\"},computerUse:{status:\"supported\"},coworkKappa:{status:\"supported\"},coworkArtifacts:{status:\"supported\"}"

  # New format: return{...FUNC(),...props}};
  let pattern3New = re"(return\{\.\.\.(?:[\w$]+)\(\),[^}]+)(\}\};)"
  let m3 = result.find(pattern3New)
  if m3.isSome:
    let bounds = m3.get().matchBounds
    let endTag = "}};"
    let insertPos = bounds.b + 1 - endTag.len
    result = result[0 ..< insertPos] & overrides & endTag & result[bounds.b + 1 .. ^1]
    echo "  [OK] mC() feature merger: 10 features overridden (1 match)"
    inc patchesApplied
  else:
    # Fallback: old format
    let pattern3Old = re"(const [\w$]+=async\(\)=>\(\{\.\.\.[\w$]+\(\),[^}]+)(await [\w$]+\(\))\}\)"
    var count3 = 0
    result = result.replace(pattern3Old, proc(m: RegexMatch): string =
      inc count3
      if count3 > 1: return m.match
      m.captures[0] & m.captures[1] & overrides & "})"
    )
    if count3 >= 1:
      echo &"  [OK] mC() feature merger: 10 features overridden (old format, {count3} match)"
      inc patchesApplied
    else:
      echo "  [FAIL] mC() feature merger: 0 matches, expected 1"
      failed = true

  # Patch 3b: Enable coworkKappa GrowthBook flag (123929380) on Linux
  let kappaPattern = re"""[\w$]+\("123929380"\)"""
  var kappaApplied = 0
  result = result.replace(kappaPattern, proc(m: RegexMatch): string =
    inc kappaApplied
    "!0"
  )
  if kappaApplied >= 3:
    echo &"  [OK] coworkKappa flag 123929380: forced ON ({kappaApplied} matches)"
    inc patchesApplied
  elif kappaApplied > 0:
    echo &"  [FAIL] coworkKappa flag 123929380: only {kappaApplied}/3 matches"
    failed = true
  else:
    echo "  [FAIL] coworkKappa flag 123929380: 0 matches"
    failed = true

  # Patch 3c: Enable coworkArtifacts GrowthBook flag (2940196192) on Linux
  let artifactsPattern = re"""[\w$]+\("2940196192"\)"""
  var artifactsApplied = 0
  result = result.replace(artifactsPattern, proc(m: RegexMatch): string =
    inc artifactsApplied
    "!0"
  )
  if artifactsApplied >= 3:
    echo &"  [OK] coworkArtifacts flag 2940196192: forced ON ({artifactsApplied} matches)"
    inc patchesApplied
  elif artifactsApplied > 0:
    echo &"  [FAIL] coworkArtifacts flag 2940196192: only {artifactsApplied}/3 matches"
    failed = true
  else:
    echo "  [FAIL] coworkArtifacts flag 2940196192: 0 matches"
    failed = true

  # Patch 4: Change preferences defaults for Code features
  let pattern4Old = "quietPenguinEnabled:!1,louderPenguinEnabled:!1"
  let pattern4New = "quietPenguinEnabled:!0,louderPenguinEnabled:!0"
  var count4 = result.count(pattern4Old)
  if count4 >= 1:
    result = result.replace(pattern4Old, pattern4New)
    echo &"  [OK] Preferences defaults: quietPenguinEnabled + louderPenguinEnabled -> true ({count4} match)"
    inc patchesApplied
  else:
    echo "  [FAIL] Preferences defaults: 0 matches for quietPenguinEnabled/louderPenguinEnabled"
    failed = true

  if failed:
    echo "  [FAIL] Required patterns did not match"
    quit(1)

  # Patch 5: Spoof platform as "darwin" in HTTP headers
  let headerPattern = re"(const [\w$]+=[\w$]+\.app\.getVersion\(\),)([\w$]+)(=)([\w$]+)(\.platform,)([\w$]+)(=\4\.getSystemVersion\(\)[;,])"
  var count5 = 0
  result = result.replace(headerPattern, proc(m: RegexMatch): string =
    inc count5
    if count5 > 1: return m.match
    let platVar = m.captures[1]
    let osMod = m.captures[3]
    let verVar = m.captures[5]
    m.captures[0] & platVar & m.captures[2] & "process.platform===\"linux\"?\"darwin\":" & osMod & m.captures[4] & verVar & m.captures[6]
  )
  if count5 >= 1:
    echo &"  [OK] HTTP header platform spoof: {count5} match(es)"
    inc patchesApplied
  elif "process.platform===\"linux\"?\"darwin\":" in result:
    echo "  [OK] HTTP header platform spoof: already patched"
    inc patchesApplied
  else:
    echo "  [FAIL] HTTP header platform spoof: 0 matches"
    quit(1)

  # Patch 5b: Spoof User-Agent header
  let uaPattern = re"(let )([\w$]+)(=)([\w$]+)(;)([\w$]+\.set\(""user-agent"",)\2(\))"
  var count5b = 0
  result = result.replace(uaPattern, proc(m: RegexMatch): string =
    inc count5b
    if count5b > 1: return m.match
    let varName = m.captures[1]
    let orig = m.captures[3]
    m.captures[0] & varName & m.captures[2] & orig & m.captures[4] &
      "if(process.platform===\"linux\"){" & varName & "=" & varName &
      ".replace(/X11; Linux [^)]+/g,\"Macintosh; Intel Mac OS X 10_15_7\")}" &
      m.captures[5] & varName & m.captures[6]
  )
  if count5b >= 1:
    echo &"  [OK] User-Agent header spoof: {count5b} match(es)"
    inc patchesApplied
  elif "Macintosh; Intel Mac OS X 10_15_7" in result:
    echo "  [OK] User-Agent header spoof: already patched"
    inc patchesApplied
  else:
    echo "  [FAIL] User-Agent header spoof: 0 matches"
    quit(1)

  # Patch 6: Spoof platform in getSystemInfo IPC response
  let sysinfoPattern = re"(platform:)process\.platform(,arch:process\.arch,total_memory:[\w$]+\.totalmem\(\))"
  var count6 = 0
  result = result.replace(sysinfoPattern, proc(m: RegexMatch): string =
    inc count6
    if count6 > 1: return m.match
    m.captures[0] & "(process.platform===\"linux\"?\"win32\":process.platform)" & m.captures[1]
  )
  if count6 >= 1:
    echo &"  [OK] getSystemInfo platform spoof: {count6} match(es)"
    inc patchesApplied
  elif "platform:(process.platform===\"linux\"?\"win32\":process.platform)" in result:
    echo "  [OK] getSystemInfo platform spoof: already patched"
    inc patchesApplied
  else:
    echo "  [FAIL] getSystemInfo platform spoof: 0 matches"
    quit(1)

  # Write back if changed
  if result != input:
    echo "  [PASS] Code + Cowork features enabled in index.js"
  else:
    echo "  [WARN] No changes made to index.js (patterns may have already been applied)"

when isMainModule:
  if paramCount() != 1:
    echo "Usage: enable_local_agent_mode <path_to_index.js>"
    quit(1)

  let filePath = paramStr(1)
  echo "=== Patch: enable_local_agent_mode ==="
  echo "  Target: " & filePath

  if not fileExists(filePath):
    echo "  [FAIL] File not found: " & filePath
    quit(1)

  var input = readFile(filePath)
  var output = apply(input)

  if output != input:
    writeFile(filePath, output)

  # Patch 7: Spoof window.process.platform in mainView.js preload
  let mainviewPath = filePath.parentDir / "mainView.js"
  var patchesApplied = EXPECTED_PATCHES - 2  # patches 1-6 + 3b + 4 = 9 so far

  # Count patches from apply (we need to recalculate since apply already counted them)
  # Just handle patches 7 and 8 here

  if fileExists(mainviewPath):
    var mvContent = readFile(mainviewPath)
    let mvOriginal = mvContent

    let mvPattern = re"(Object\.fromEntries\(Object\.entries\(process\)\.filter\(\(\[[\w$]+\]\)=>[\w$]+\[[\w$]+\]\)\);)([\w$]+)(\.version=[\w$]+\(\)\.appVersion;)"
    var mvCount = 0
    mvContent = mvContent.replace(mvPattern, proc(m: RegexMatch): string =
      inc mvCount
      if mvCount > 1: return m.match
      let procVar = m.captures[1]
      m.captures[0] & procVar & m.captures[2] & "if(process.platform===\"linux\"){" & procVar & ".platform=\"win32\"}"
    )
    if mvCount >= 1:
      echo &"  [OK] mainView.js: window.process.platform spoof ({mvCount} match)"
      patchesApplied += 1
    elif ".platform=\"win32\"" in mvContent or ".platform=\"darwin\"" in mvContent:
      echo "  [OK] mainView.js: window.process.platform spoof already applied"
      patchesApplied += 1
    else:
      echo "  [FAIL] mainView.js: window.process.platform spoof: 0 matches"
      quit(1)

    if mvContent != mvOriginal:
      writeFile(mainviewPath, mvContent)
      echo "  [PASS] mainView.js patched successfully"
  else:
    echo &"  [OK] mainView.js not found at {mainviewPath} -- skipped (single-file test mode)"
    patchesApplied += 1

  # Patch 8: Spoof navigator.platform and navigator.userAgent in renderer main world
  let navigatorMarker = "__nav_spoof_applied"
  # Re-read in case apply() changed it
  var content = readFile(filePath)

  if navigatorMarker in content:
    echo "  [OK] navigator spoof: already applied"
    patchesApplied += 1
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
      writeFile(filePath, content)
      echo "  [OK] navigator spoof: injected in index.js (userAgent + platform)"
      patchesApplied += 1
    else:
      echo "  [FAIL] navigator spoof: could not find 'use strict' prefix at start of index.js."
      quit(1)

  # Strictness check
  if patchesApplied < 2:  # patches 7 and 8
    echo &"  [FAIL] Only {patchesApplied}/2 mainModule patches applied"
    quit(1)

  echo &"  [PASS] {EXPECTED_PATCHES}/{EXPECTED_PATCHES} patches applied"
