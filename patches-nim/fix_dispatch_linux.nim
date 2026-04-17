# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
# Nim port of fix_dispatch_linux.py for benchmarking.
# Uses std/nre (PCRE) because this patch needs backreferences.

import std/[os, strformat, strutils, options]
import std/nre

proc apply*(input: string): string =
  var content = input
  var patchesApplied = 0
  let original = input

  # Patch A: force sessions-bridge init gate ON
  let gateAlready = re"""let (?:[\w$]+=!(?:0|1),)*[\w$]+=!0;const [\w$]+=async\(\)=>\{if\(![\w$]+\)\{[\w$]+\.info\("\[sessions-bridge\] init skipped"""
  if content.find(gateAlready).isSome:
    echo "  [OK] Sessions-bridge gate: already patched"
    inc patchesApplied
  else:
    let gate = re"""(let (?:[\w$]+=!1,)*)([\w$]+)(=)(!1)(;const [\w$]+=async\(\)=>\{if\(!\2\)\{[\w$]+\.info\("\[sessions-bridge\] init skipped)"""
    var count = 0
    content = content.replace(gate, proc (m: RegexMatch): string =
      inc count
      m.captures[0] & m.captures[1] & m.captures[2] & "!0" & m.captures[4]
    )
    if count >= 1:
      echo &"  [OK] Sessions-bridge gate: forced ON ({count})"
      inc patchesApplied
    else:
      echo "  [FAIL] Sessions-bridge gate: pattern not found"

  # Patch B: bypass remote session control
  let remote = re"""![\w$]+\("2216414644"\)"""
  if content.find(remote).isNone:
    if content.contains("Remote session control is disabled"):
      echo "  [OK] Remote session control: already patched"
      inc patchesApplied
    else:
      echo "  [FAIL] Remote session control: pattern not found"
  else:
    var count = 0
    content = content.replace(remote, proc (m: RegexMatch): string =
      inc count
      "!1"
    )
    if count >= 1:
      echo &"  [OK] Remote session control: bypassed ({count})"
      inc patchesApplied

  # Patch C
  let platformOld = "default:return\"Unsupported Platform\""
  let platformNew = "case\"linux\":return\"Linux\";default:return\"Unsupported Platform\""
  if content.contains(platformNew):
    echo "  [OK] Platform label: already patched"
    inc patchesApplied
  elif content.contains(platformOld):
    content = content.replace(platformOld, platformNew)
    echo "  [OK] Platform label: added Linux"
    inc patchesApplied
  else:
    echo "  [FAIL] Platform label: pattern not found"

  # Patch D: telemetry gate
  let telemetryAlready = re"""([\w$]+)(=process\.platform==="darwin",)([\w$]+)(=process\.platform==="win32",)([\w$]+)=\1\|\|\3\|\|process\.platform==="linux""""
  if content.find(telemetryAlready).isSome:
    echo "  [OK] Telemetry gate: already patched"
    inc patchesApplied
  else:
    let telemetry = re"""([\w$]+)(=process\.platform==="darwin",)([\w$]+)(=process\.platform==="win32",)([\w$]+)=\1\|\|\3"""
    var count = 0
    content = content.replace(telemetry, proc (m: RegexMatch): string =
      inc count
      m.match & "||process.platform===\"linux\""
    )
    if count >= 1:
      echo &"  [OK] Telemetry gate: included Linux ({count})"
      inc patchesApplied
    else:
      echo "  [FAIL] Telemetry gate: pattern not found"

  # Patch E: Jr() override
  let jrTarget = "if(t===\"3558849738\")return!0;"
  let jrStale = "if(t===\"3558849738\"||t===\"1143815894\")return!0;"
  if content.contains(jrStale):
    content = content.replace(jrStale, jrTarget)
    echo "  [OK] Jr() override: removed stale hostLoopMode"
    inc patchesApplied
  elif content.contains(jrTarget):
    echo "  [OK] Jr() override: already patched"
    inc patchesApplied
  else:
    let blanket = re"""(return!0;)(const [\w$]+=[\w$]+\[[\w$]+\];return)"""
    content = content.replace(blanket, proc (m: RegexMatch): string = m.captures[1])
    let jr = re"""(function )([\w$]+)(\()([\w$]+)(\)\{)(const [\w$]+=[\w$]+\[\4\];return\([\w$]+==null\?void 0:[\w$]+\.on\)\?\?!1\})"""
    var count = 0
    content = content.replace(jr, proc (m: RegexMatch): string =
      inc count
      let param = m.captures[3]
      m.captures[0] & m.captures[1] & m.captures[2] & m.captures[3] & m.captures[4] &
        &"if({param}===\"3558849738\")return!0;" & m.captures[5]
    )
    if count >= 1:
      echo &"  [OK] Jr() override: injected ({count})"
      inc patchesApplied
    else:
      echo "  [FAIL] Jr() override: pattern not found"

  # Patch F: rjt() text forward
  let rjtAlready = re"""if\(\(([\w$]+)==null\?void 0:\1\.type\)==="tool_use"&&\(\1\.name==="SendUserMessage"\|\|\1\.name==="mcp__dispatch__send_message"\|\|\1\.name==="mcp__cowork__present_files"\)\)return!0\}return [\w$]+\.some\(function\(j\)\{return j&&j\.type==="text"&&j\.text\}\)\}"""
  if content.find(rjtAlready).isSome:
    echo "  [OK] rjt() text forward: already patched"
    inc patchesApplied
  else:
    let rjt = re"""for\(const ([\w$]+) of ([\w$]+)\)\{const ([\w$]+)=\1;if\(\(\3==null\?void 0:\3\.type\)==="tool_use"&&\3\.name==="SendUserMessage"\)return!0\}return!1\}"""
    let m = content.find(rjt)
    if m.isSome:
      let mm = m.get
      let loopVar = mm.captures[0]
      let arrayVar = mm.captures[1]
      let itemVar = mm.captures[2]
      let replacement =
        &"for(const {loopVar} of {arrayVar}){{const {itemVar}={loopVar};" &
        &"if(({itemVar}==null?void 0:{itemVar}.type)===\"tool_use\"&&(" &
        &"{itemVar}.name===\"SendUserMessage\"||" &
        &"{itemVar}.name===\"mcp__dispatch__send_message\"||" &
        &"{itemVar}.name===\"mcp__cowork__present_files\"))return!0}}" &
        &"return {arrayVar}.some(function(j){{return j&&j.type===\"text\"&&j.text}})}}"
      let s = mm.matchBounds
      content = content[0 ..< s.a] & replacement & content[s.b + 1 .. ^1]
      echo "  [OK] rjt() text forward: patched"
      inc patchesApplied
    else:
      echo "  [FAIL] rjt() text forward: pattern not found"

  # Patch J: auto-wake dispatch parent
  if content.contains("Auto-waking cold parent"):
    echo "  [OK] dispatch auto-wake parent: already patched"
    inc patchesApplied
  else:
    let wake = re"""(\(\(([\w$]+)\.pendingDispatchNotifications\?\?\(\2\.pendingDispatchNotifications=\[\]\)\)\.push\(([\w$]+)\),)([\w$]+)(\.info\(`\[Dispatch\] Queued notification for cold parent \$\{\2\.sessionId\} \(child \$\{([\w$]+)\.sessionId\} \$\{([\w$]+)\}\)`\)\))"""
    let m = content.find(wake)
    if m.isSome:
      let mm = m.get
      let g1 = mm.captures[0]
      let sessionVar = mm.captures[1]
      let notifVar = mm.captures[2]
      let logger = mm.captures[3]
      let g5 = mm.captures[4]
      let tail = g5[0 ..< g5.len - 1]
      let replacement =
        g1 & logger & tail &
        &",setTimeout(()=>{{{logger}.info(`[Dispatch] Auto-waking cold parent ${{{sessionVar}.sessionId}}`);" &
        &"this.sendMessage({sessionVar}.sessionId,{notifVar}).catch(x=>{logger}.error(`[Dispatch] Auto-wake failed for ${{{sessionVar}.sessionId}}:`,x))}},500))"
      let s = mm.matchBounds
      content = content[0 ..< s.a] & replacement & content[s.b + 1 .. ^1]
      echo "  [OK] dispatch auto-wake parent: injected"
      inc patchesApplied
    else:
      echo "  [FAIL] dispatch auto-wake parent: pattern not found"

  const EXPECTED = 7
  if patchesApplied < EXPECTED:
    raise newException(ValueError, &"Only {patchesApplied}/{EXPECTED} patches applied")

  if content == original:
    return content

  let origDelta = original.count('{') - original.count('}')
  let newDelta = content.count('{') - content.count('}')
  if origDelta != newDelta:
    raise newException(ValueError, &"Brace imbalance: {newDelta - origDelta} unmatched braces")

  result = content

when isMainModule:
  let file = paramStr(1)
  echo "=== Patch: fix_dispatch_linux ==="
  echo &"  Target: {file}"
  let input = readFile(file)
  let output = apply(input)
  if output != input:
    writeFile(file, output)
  echo "  [PASS]"
