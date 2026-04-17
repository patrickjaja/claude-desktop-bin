# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
# Nim port of fix_buddy_ble_linux.py

import std/[os, strformat, strutils]
import regex

const EXPECTED_PATCHES = 2

proc extractEipcUuid(content: string): string =
  let p = re2"\$eipc_message\$_([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})"
  var m: RegexMatch2
  if content.find(p, m):
    result = content[m.group(0)]
  else:
    result = ""

proc buildEarlyStubsJs(eipcPrefix: string): string =
  let buddy = eipcPrefix & "claude.buddy_$_Buddy_$_"
  let ble = eipcPrefix & "claude.buddy_$_BuddyBleTransport_$_"

  result = "if(process.platform===\"linux\"){" &
    "const _bi=require(\"electron\").ipcMain;" &
    &"_bi.handle(\"{ble}reportState\",()=>{{}});" &
    &"_bi.handle(\"{ble}rx\",()=>{{}});" &
    &"_bi.handle(\"{ble}log\",()=>{{}});" &
    &"_bi.handle(\"{buddy}status\",()=>({{connected:false,error:null,paired:false}}));" &
    &"_bi.handle(\"{buddy}deviceStatus\",()=>null);" &
    &"_bi.handle(\"{buddy}setName\",()=>null);" &
    &"_bi.handle(\"{buddy}pairDevice\",()=>\"\");" &
    &"_bi.handle(\"{buddy}scanDevices\",()=>[]);" &
    &"_bi.handle(\"{buddy}pickDevice\",()=>false);" &
    &"_bi.handle(\"{buddy}cancelScan\",()=>{{}});" &
    &"_bi.handle(\"{buddy}forgetDevice\",()=>{{}});" &
    &"_bi.handle(\"{buddy}pickFolder\",()=>null);" &
    &"_bi.handle(\"{buddy}preview\",()=>null);" &
    &"_bi.handle(\"{buddy}install\",()=>{{}});" &
    "}"

proc apply*(input: string): string =
  var content = input
  let original = input
  var patchesApplied = 0

  if not content.contains("BuddyBleTransport"):
    echo "  [SKIP] No BuddyBleTransport references (feature not present)"
    return content

  # ── Patch A: Force feature flag
  let alreadyA = content.contains("process.platform===\"linux\"||") and content.contains("\"2358734848\"")
  if alreadyA:
    echo "  [OK] Buddy flag: already patched (skipped)"
    patchesApplied += 1
  else:
    let flagPattern = re2"""(const [\w$]+="2358734848",)([\w$]+=\(\)=>)([\w$]+\([\w$]+\))"""
    var found = false
    var count = 0
    content = content.replace(flagPattern, proc (m: RegexMatch2, s: string): string =
      if found: return s[m.boundaries]
      found = true
      inc count
      let g1 = s[m.group(0)]
      let g2 = s[m.group(1)]
      let g3 = s[m.group(2)]
      g1 & g2 & "process.platform===\"linux\"||" & g3
    )
    if count >= 1:
      echo &"  [OK] Buddy flag: forced ON for Linux ({count} match)"
      patchesApplied += 1
    else:
      echo "  [FAIL] Buddy flag pattern not found"
      raise newException(ValueError, "fix_buddy_ble_linux: Buddy flag pattern not found")

  # ── Patch B: Early IPC stubs
  let alreadyB = content.contains("_bi=require(\"electron\").ipcMain")
  if alreadyB:
    echo "  [OK] Early stubs: already patched (skipped)"
    patchesApplied += 1
  else:
    let uuid = extractEipcUuid(content)
    if uuid.len == 0:
      echo "  [FAIL] Could not extract eipc UUID"
      raise newException(ValueError, "fix_buddy_ble_linux: could not extract eipc UUID")

    let eipcPrefix = &"$eipc_message$_{uuid}_$_"
    echo &"  [OK] Extracted eipc UUID: {uuid}"

    let stubJs = buildEarlyStubsJs(eipcPrefix)

    let pattern = re2"""(app\.on\("ready",async\(\)=>\{)"""
    var found = false
    var count = 0
    content = content.replace(pattern, proc (m: RegexMatch2, s: string): string =
      if found: return s[m.boundaries]
      found = true
      inc count
      s[m.boundaries] & stubJs
    )
    if count >= 1:
      echo &"  [OK] Early stubs: injected at app.on('ready') ({count} match)"
      patchesApplied += 1
    else:
      echo "  [FAIL] app.on(\"ready\") pattern: 0 matches"
      raise newException(ValueError, "fix_buddy_ble_linux: app.on(ready) not found")

  if patchesApplied < EXPECTED_PATCHES:
    echo &"  [FAIL] Only {patchesApplied}/{EXPECTED_PATCHES} patches applied"
    raise newException(ValueError, &"fix_buddy_ble_linux: only {patchesApplied}/{EXPECTED_PATCHES} applied")

  result = content

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_buddy_ble_linux <file>"
    quit(1)
  let file = paramStr(1)
  echo "=== Patch: fix_buddy_ble_linux ==="
  echo &"  Target: {file}"
  let input = readFile(file)
  let output = apply(input)
  if output != input:
    writeFile(file, output)
    echo "  [PASS] Buddy BLE enabled on Linux (flag + early stubs)"
  else:
    echo "  [OK] Already patched, no changes needed"
