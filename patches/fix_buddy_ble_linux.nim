# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
# Enable Hardware Buddy (Nibblet BLE device) on Linux.
# Two patches: force GrowthBook flag and early IPC stubs.

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

proc extractEipcUuid(content: string): string =
  let pat =
    re2"\$eipc_message\$_([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})"
  for m in content.findAll(pat):
    return content[m.group(0)]
  return ""

proc buildEarlyStubsJs(eipcPrefix: string): string =
  let buddy = eipcPrefix & "claude.buddy_$_Buddy_$_"
  let ble = eipcPrefix & "claude.buddy_$_BuddyBleTransport_$_"
  result =
    "if(process.platform===\"linux\"){" & "const _bi=require(\"electron\").ipcMain;" &
    "_bi.handle(\"" & ble & "reportState\",()=>{});" & "_bi.handle(\"" & ble &
    "rx\",()=>{});" & "_bi.handle(\"" & ble & "log\",()=>{});" & "_bi.handle(\"" & buddy &
    "status\",()=>({connected:false,error:null,paired:false}));" & "_bi.handle(\"" &
    buddy & "deviceStatus\",()=>null);" & "_bi.handle(\"" & buddy &
    "setName\",()=>null);" & "_bi.handle(\"" & buddy & "pairDevice\",()=>\"\");" &
    "_bi.handle(\"" & buddy & "scanDevices\",()=>[]);" & "_bi.handle(\"" & buddy &
    "pickDevice\",()=>false);" & "_bi.handle(\"" & buddy & "cancelScan\",()=>{});" &
    "_bi.handle(\"" & buddy & "forgetDevice\",()=>{});" & "_bi.handle(\"" & buddy &
    "pickFolder\",()=>null);" & "_bi.handle(\"" & buddy & "preview\",()=>null);" &
    "_bi.handle(\"" & buddy & "install\",()=>{});" & "}"

proc apply*(input: string): string =
  result = input
  var patchesApplied = 0

  if "BuddyBleTransport" notin result:
    echo "  [SKIP] No BuddyBleTransport references (feature not present)"
    return result

  # Patch A: Force the Buddy feature flag on Linux
  let alreadyA =
    "process.platform===\"linux\"||" in result and "\"2358734848\"" in result
  if alreadyA:
    echo "  [OK] Buddy flag: already patched (skipped)"
    patchesApplied += 1
  else:
    let flagPattern =
      re2"(const [\w$]+=""2358734848"",)([\w$]+=\(\)=>)([\w$]+\([\w$]+\))"
    var countFlag = result.replaceFirst(
      flagPattern,
      proc(m: RegexMatch2, s: string): string =
        s[m.group(0)] & s[m.group(1)] & "process.platform===\"linux\"||" & s[m.group(2)],
    )
    if countFlag >= 1:
      echo &"  [OK] Buddy flag: forced ON for Linux ({countFlag} match)"
      patchesApplied += 1
    else:
      echo "  [FAIL] Buddy flag pattern not found"
      raise
        newException(ValueError, "fix_buddy_ble_linux: Buddy flag pattern not found")

  # Patch B: Early IPC stubs to prevent race condition
  let alreadyB = "_bi=require(\"electron\").ipcMain" in result
  if alreadyB:
    echo "  [OK] Early stubs: already patched (skipped)"
    patchesApplied += 1
  else:
    let uuid = extractEipcUuid(result)
    if uuid == "":
      echo "  [FAIL] Could not extract eipc UUID"
      raise newException(ValueError, "fix_buddy_ble_linux: Could not extract eipc UUID")

    let eipcPrefix = "$eipc_message$_" & uuid & "_$_"
    echo &"  [OK] Extracted eipc UUID: {uuid}"

    let stubJs = buildEarlyStubsJs(eipcPrefix)

    let pattern = re2"(app\.on\(""ready"",async\(\)=>\{)"
    var countStub = result.replaceFirst(
      pattern,
      proc(m: RegexMatch2, s: string): string =
        s[m.group(0)] & stubJs,
    )
    if countStub >= 1:
      echo &"  [OK] Early stubs: injected at app.on('ready') ({countStub} match)"
      patchesApplied += 1
    else:
      echo "  [FAIL] app.on(\"ready\") pattern: 0 matches"
      raise newException(
        ValueError, "fix_buddy_ble_linux: app.on(\"ready\") pattern not found"
      )

  if patchesApplied < EXPECTED_PATCHES:
    raise newException(
      ValueError,
      &"fix_buddy_ble_linux: Only {patchesApplied}/{EXPECTED_PATCHES} patches applied",
    )

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_buddy_ble_linux <file>"
    quit(1)
  let file = paramStr(1)
  echo "=== Patch: fix_buddy_ble_linux ==="
  echo &"  Target: {file}"
  if not fileExists(file):
    echo &"  [FAIL] File not found: {file}"
    quit(1)
  let input = readFile(file)
  let output = apply(input)
  if output != input:
    writeFile(file, output)
    echo "  [PASS] Buddy BLE enabled on Linux (flag + early stubs)"
  else:
    echo "  [OK] Already patched, no changes needed"
