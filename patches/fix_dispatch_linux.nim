# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
#
# Enable Dispatch (remote task orchestration) on Linux.
#
# Seven-part patch (A-F, J):
# A. Force sessions-bridge init gate ON.
# B. Bypass remote session control check.
# C. Add Linux to the HI() platform label.
# D. Include Linux in the Xqe telemetry gate.
# E. Override Jr() for Linux-critical GrowthBook flags.
# F. Fix rjt() to forward text responses.
# J. Auto-wake dispatch parent when child task completes.

import std/[os, strformat, strutils]
import std/nre

const EXPECTED_PATCHES = 7

proc apply*(input: string): string =
  result = input
  var patchesApplied = 0

  # -- Patch A: Force sessions-bridge init gate ON --
  # Strategy: find the gate variable name from the if-check near
  # "[sessions-bridge] init skipped", then flip its =!1 to =!0 in the let decl.
  # The gate var may appear anywhere in the comma-separated let list (not
  # necessarily last), so we avoid a single backreference-based regex.
  let gateFinderRe =
    re"""let (?:[\w$]+=![01],)*[\w$]+=![01];const [\w$]+=async\(\)=>\{if\(!([\w$]+)\)\{[\w$]+\.info\("\[sessions-bridge\] init skipped"""
  let gateFinderMatch = result.find(gateFinderRe)
  if gateFinderMatch.isSome:
    let m = gateFinderMatch.get()
    let gateVar = m.captures[0]
    # Check if it's already patched (=!0)
    if (gateVar & "=!0") in m.match:
      echo "  [OK] Sessions-bridge gate: already patched (skipped)"
      inc patchesApplied
    else:
      # Replace gateVar=!1 with gateVar=!0 near the init function.
      # We match the whole let...;const... span to ensure we only touch the right one.
      let fullSpan = m.match
      let patched = fullSpan.replace(gateVar & "=!1", gateVar & "=!0")
      if patched != fullSpan:
        result = result.replace(fullSpan, patched)
        echo &"  [OK] Sessions-bridge gate: forced {gateVar}=!0"
        inc patchesApplied
      else:
        echo &"  [FAIL] Sessions-bridge gate: found gate var '{gateVar}' but could not flip to !0"
  else:
    echo "  [FAIL] Sessions-bridge gate: pattern not found"

  # -- Patch B: Bypass remote session control check --
  let remotePattern = re"""![\w$]+\("2216414644"\)"""
  if not result.find(remotePattern).isSome:
    if "Remote session control is disabled" in result:
      echo "  [OK] Remote session control: already patched (skipped)"
      inc patchesApplied
    else:
      echo "  [FAIL] Remote session control: pattern not found"
  else:
    var countB = 0
    result = result.replace(
      remotePattern,
      proc(m: RegexMatch): string =
        inc countB
        "!1",
    )
    if countB >= 1:
      echo &"  [OK] Remote session control: bypassed ({countB} matches)"
      inc patchesApplied
    else:
      echo "  [FAIL] Remote session control: pattern not found"

  # -- Patch C: Add Linux to HI() platform label --
  let platformOld = "default:return\"Unsupported Platform\""
  let platformNew =
    "case\"linux\":return\"Linux\";default:return\"Unsupported Platform\""

  if platformNew in result:
    echo "  [OK] Platform label: already patched (skipped)"
    inc patchesApplied
  elif platformOld in result:
    result = result.replace(platformOld, platformNew)
    echo "  [OK] Platform label: added Linux to HI()"
    inc patchesApplied
  else:
    echo "  [FAIL] Platform label: pattern not found"

  # -- Patch D: Include Linux in Xqe telemetry gate --
  # Backreferences: \1 and \3 ensure same var names in combined expression
  let telemetryAlready = re(
    "([\\w$]+)(=process\\.platform===\"darwin\",)([\\w$]+)(=process\\.platform===\"win32\",)([\\w$]+)=\\1\\|\\|\\3\\|\\|process\\.platform===\"linux\""
  )
  if result.find(telemetryAlready).isSome:
    echo "  [OK] Telemetry gate: already patched (skipped)"
    inc patchesApplied
  else:
    let telemetryPattern = re(
      "([\\w$]+)(=process\\.platform===\"darwin\",)([\\w$]+)(=process\\.platform===\"win32\",)([\\w$]+)=\\1\\|\\|\\3"
    )
    var countD = 0
    result = result.replace(
      telemetryPattern,
      proc(m: RegexMatch): string =
        inc countD
        if countD > 1:
          return m.match
        m.match & "||process.platform===\"linux\"",
    )
    if countD >= 1:
      echo &"  [OK] Telemetry gate: included Linux ({countD} match)"
      inc patchesApplied
    else:
      echo "  [FAIL] Telemetry gate: pattern not found"

  # -- Patch E: Override Jr() for dispatch agent name flag --
  let jrAlready = re"""if\([\w$]+===\"3558849738\"\)return!0;"""
  let jrStaleBothRe =
    re"""if\(([\w$]+)===\"3558849738\"\|\|\1===\"1143815894\"\)return!0;"""
  if result.find(jrStaleBothRe).isSome:
    result = result.replace(
      jrStaleBothRe,
      proc(m: RegexMatch): string =
        "if(" & m.captures[0] & "===\"3558849738\")return!0;",
    )
    echo "  [OK] Jr() dispatch flag override: removed stale hostLoopMode override"
    inc patchesApplied
  elif result.find(jrAlready).isSome:
    echo "  [OK] Jr() dispatch flag override: already patched (skipped)"
    inc patchesApplied
  else:
    # Remove stale blanket override if present
    let blanketMarker = re"(return!0;)(const [\w$]+=[\w$]+\[[\w$]+\];return)"
    result = result.replace(
      blanketMarker,
      proc(m: RegexMatch): string =
        m.captures[1],
    )

    let jrPattern =
      re"(function )([\w$]+)(\()([\w$]+)(\)\{)(const [\w$]+=[\w$]+\[\4\];return\([\w$]+==null\?void 0:[\w$]+\.on\)\?\?!1\})"
    var countE = 0
    result = result.replace(
      jrPattern,
      proc(m: RegexMatch): string =
        inc countE
        if countE > 1:
          return m.match
        let param = m.captures[3]
        m.captures[0] & m.captures[1] & m.captures[2] & m.captures[3] & m.captures[4] &
          "if(" & param & "===\"3558849738\")return!0;" & m.captures[5],
    )
    if countE >= 1:
      echo &"  [OK] Jr() dispatch flag override: injected ({countE} match)"
      inc patchesApplied
    else:
      echo "  [FAIL] Jr() dispatch flag override: pattern not found"

  # -- Patch F: Fix rjt() to forward text responses --
  # Upstream now has: (name==="SendUserMessage"||t&&(name===SU||name===T4))
  # We add mcp__dispatch__send_message and mcp__cowork__present_files, plus text forwarding.
  let rjtAlready =
    re"""mcp__dispatch__send_message.{0,80}mcp__cowork__present_files.{0,80}\.some\(function\(j\)\{return j&&j\.type==="text"&&j\.text\}\)"""
  if result.find(rjtAlready).isSome:
    echo "  [OK] rjt() text forward: already patched (skipped)"
    inc patchesApplied
  else:
    # Match new upstream pattern: ...name==="SendUserMessage"||t&&(name===VAR||name===VAR)))return!0}return!1}
    let rjtPattern =
      re"""for\(const ([\w$]+) of ([\w$]+)\)\{const ([\w$]+)=\1;if\(\(\3==null\?void 0:\3\.type\)==="tool_use"&&\(\3\.name==="SendUserMessage"\|\|([\w$]+)&&\(\3\.name===([\w$]+)\|\|\3\.name===([\w$]+)\)\)\)return!0\}return!1\}"""
    let rjtMatch = result.find(rjtPattern)
    if rjtMatch.isSome:
      let m = rjtMatch.get()
      let loopVar = m.captures[0]
      let arrayVar = m.captures[1]
      let itemVar = m.captures[2]
      let gateVar = m.captures[3]
      let toolVar1 = m.captures[4]
      let toolVar2 = m.captures[5]
      let rjtReplacement =
        "for(const " & loopVar & " of " & arrayVar & "){const " & itemVar & "=" & loopVar &
        ";" & "if((" & itemVar & "==null?void 0:" & itemVar & ".type)===\"tool_use\"&&(" &
        itemVar & ".name===\"SendUserMessage\"||" & itemVar &
        ".name===\"mcp__dispatch__send_message\"||" & itemVar &
        ".name===\"mcp__cowork__present_files\"||" & gateVar & "&&(" & itemVar &
        ".name===" & toolVar1 & "||" & itemVar & ".name===" & toolVar2 & ")))return!0}" &
        "return " & arrayVar & ".some(function(j){return j&&j.type===\"text\"&&j.text})}"
      let bounds = m.matchBounds
      result = result[0 ..< bounds.a] & rjtReplacement & result[bounds.b + 1 .. ^1]
      echo &"  [OK] rjt() text forward: patched (item={itemVar}, array={arrayVar}, gate={gateVar})"
      inc patchesApplied
    else:
      # Fallback: try old pattern (no dispatch tool gate)
      let rjtPatternOld =
        re"for\(const ([\w$]+) of ([\w$]+)\)\{const ([\w$]+)=\1;if\(\(\3==null\?void 0:\3\.type\)===""tool_use""&&\3\.name===""SendUserMessage""\)return!0\}return!1\}"
      let rjtMatchOld = result.find(rjtPatternOld)
      if rjtMatchOld.isSome:
        let m = rjtMatchOld.get()
        let loopVar = m.captures[0]
        let arrayVar = m.captures[1]
        let itemVar = m.captures[2]
        let rjtReplacement =
          "for(const " & loopVar & " of " & arrayVar & "){const " & itemVar & "=" &
          loopVar & ";" & "if((" & itemVar & "==null?void 0:" & itemVar &
          ".type)===\"tool_use\"&&(" & itemVar & ".name===\"SendUserMessage\"||" &
          itemVar & ".name===\"mcp__dispatch__send_message\"||" & itemVar &
          ".name===\"mcp__cowork__present_files\"))return!0}" & "return " & arrayVar &
          ".some(function(j){return j&&j.type===\"text\"&&j.text})}"
        let bounds = m.matchBounds
        result = result[0 ..< bounds.a] & rjtReplacement & result[bounds.b + 1 .. ^1]
        echo &"  [OK] rjt() text forward: patched via old pattern (item={itemVar}, array={arrayVar})"
        inc patchesApplied
      else:
        echo "  [FAIL] rjt() text forward: pattern not found"

  # -- Patch J: Auto-wake dispatch parent when child task completes --
  if "Auto-waking cold parent" in result:
    echo "  [OK] dispatch auto-wake parent: already patched (skipped)"
    inc patchesApplied
  else:
    let wakePattern =
      re"(\(\(([\w$]+)\.pendingDispatchNotifications\?\?\(\2\.pendingDispatchNotifications=\[\]\)\)\.push\(([\w$]+)\),)([\w$]+)(\.info\(`\[Dispatch\] Queued notification for cold parent \$\{\2\.sessionId\} \(child \$\{([\w$]+)\.sessionId\} \$\{([\w$]+)\}\)`\)\))"
    let wakeMatch = result.find(wakePattern)
    if wakeMatch.isSome:
      let m = wakeMatch.get()
      let sessionVar = m.captures[1]
      let notifVar = m.captures[2]
      let logger = m.captures[3]
      # Build replacement: original + setTimeout auto-wake
      let origMatch = m.match
      # Strip trailing ) from the original
      let baseMatch = origMatch[0 ..< origMatch.len - 1]
      let wakeReplacement =
        baseMatch & ",setTimeout(()=>{" & logger &
        ".info(`[Dispatch] Auto-waking cold parent ${" & sessionVar & ".sessionId}`);" &
        "this.sendMessage(" & sessionVar & ".sessionId," & notifVar & ").catch(x=>" &
        logger & ".error(`[Dispatch] Auto-wake failed for ${" & sessionVar &
        ".sessionId}:`,x))},500))"
      let bounds = m.matchBounds
      result = result[0 ..< bounds.a] & wakeReplacement & result[bounds.b + 1 .. ^1]
      echo &"  [OK] dispatch auto-wake parent: injected setTimeout sendMessage (session={sessionVar}, notif={notifVar}, logger={logger})"
      inc patchesApplied
    else:
      echo "  [FAIL] dispatch auto-wake parent: pattern not found"

  # -- Results --
  if patchesApplied < EXPECTED_PATCHES:
    echo &"  [FAIL] Only {patchesApplied}/{EXPECTED_PATCHES} patches applied -- check [WARN]/[FAIL] messages above"
    quit(1)

  if result != input:
    # Verify brace balance
    let originalDelta = input.count('{') - input.count('}')
    let patchedDelta = result.count('{') - result.count('}')
    if originalDelta != patchedDelta:
      let diff = patchedDelta - originalDelta
      echo &"  [FAIL] Patch introduced brace imbalance: {diff:+d} unmatched braces"
      quit(1)

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_dispatch_linux <path_to_index.js>"
    quit(1)

  let filePath = paramStr(1)
  echo "=== Patch: fix_dispatch_linux ==="
  echo "  Target: " & filePath

  if not fileExists(filePath):
    echo "  [FAIL] File not found: " & filePath
    quit(1)

  let input = readFile(filePath)
  let output = apply(input)

  if output == input:
    echo &"  [OK] All {EXPECTED_PATCHES} patches already applied (no changes needed)"
  else:
    writeFile(filePath, output)
    echo &"  [PASS] {EXPECTED_PATCHES} patches applied"
