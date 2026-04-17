# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
# Nim port of fix_quick_entry_cli_toggle.py

import std/[os, strformat, strutils]
import regex

const TRIGGER_FLAG = "--toggle-quick-entry"
const HANDLER_GLOBAL = "__ceQuickEntryShow"

proc apply*(input: string): string =
  var content = input
  let original = input
  var applied = 0
  const EXPECTED = 3

  # ------------------------------------------------------------------
  # Sub-patch A + C: capture handler and schedule first-instance check
  # ------------------------------------------------------------------

  if strutils.contains(content, HANDLER_GLOBAL):
    echo &"  [INFO] {HANDLER_GLOBAL} already present — sub-patch A/C skipped"
    applied += 2
  else:
    let patA = re2"""([\w$]+)\(([\w$]+)\.QUICK_ENTRY,(\(\)=>\{[\w$]+&&![\w$]+\.isDestroyed\(\)&&[\w$]+\.isFullScreen\(\)\?\([\w$]+\.focus\(\),[\w$]+\(\)\):[\w$]+\(\)\})\)"""
    var countA = 0
    content = content.replace(patA, proc (m: RegexMatch2, s: string): string =
      inc countA
      let regFn = s[m.group(0)]
      let enumVar = s[m.group(1)]
      let arrow = s[m.group(2)]
      doAssert arrow.startsWith("()=>{") and arrow.endsWith("}")
      let body = arrow[5 ..< arrow.len - 1]

      let arrowWrapped = "()=>{var __t=Date.now();" &
        "if(globalThis.__ceQEInvokedAt&&__t-globalThis.__ceQEInvokedAt<900)return;" &
        "globalThis.__ceQEInvokedAt=__t;" &
        body &
        "}"
      let assign = "globalThis." & HANDLER_GLOBAL & "=" & arrowWrapped
      let firstInstance = ",setTimeout(()=>{" &
        "try{if(Array.isArray(process.argv)&&process.argv.includes(\"" &
        TRIGGER_FLAG & "\")&&globalThis." &
        HANDLER_GLOBAL & ")globalThis." &
        HANDLER_GLOBAL & "()}catch(e){}" &
        "},500)"
      regFn & "(" & enumVar & ".QUICK_ENTRY," & assign & ")" & firstInstance
    )
    if countA == 1:
      echo "  [OK] sub-patch A (handler capture) + C (first-instance schedule) applied"
      applied += 2
    elif countA > 1:
      raise newException(ValueError, &"fix_quick_entry_cli_toggle: sub-patch A matched {countA} times (expected 1)")
    else:
      raise newException(ValueError, "fix_quick_entry_cli_toggle: sub-patch A did not match QUICK_ENTRY handler registration")

  # ------------------------------------------------------------------
  # Sub-patch B: prepend argv check to second-instance handler
  # ------------------------------------------------------------------

  let bMarker = "\"" & TRIGGER_FLAG & "\")){try{globalThis."
  if strutils.contains(content, bMarker):
    echo "  [INFO] sub-patch B already applied — skipped"
    applied += 1
  else:
    let patB = re2"""(\.on\("second-instance",\()([\w$]+),([\w$]+),([\w$]+)(\)=>\{)"""
    var countB = 0
    content = content.replace(patB, proc (m: RegexMatch2, s: string): string =
      inc countB
      let head = s[m.group(0)]
      let evt = s[m.group(1)]
      let argv = s[m.group(2)]
      let cwd = s[m.group(3)]
      let tail = s[m.group(4)]
      let check = "if(Array.isArray(" & argv & ")&&" & argv &
        ".includes(\"" & TRIGGER_FLAG & "\"))" &
        "{try{globalThis." & HANDLER_GLOBAL &
        "&&globalThis." & HANDLER_GLOBAL &
        "()}catch(e){}return}"
      head & evt & "," & argv & "," & cwd & tail & check
    )
    if countB == 1:
      echo "  [OK] sub-patch B (second-instance argv check) applied"
      applied += 1
    elif countB > 1:
      raise newException(ValueError, &"fix_quick_entry_cli_toggle: sub-patch B matched {countB} times (expected 1)")
    else:
      raise newException(ValueError, "fix_quick_entry_cli_toggle: sub-patch B did not match .on(\"second-instance\", ...) handler")

  if applied < EXPECTED:
    raise newException(ValueError, &"fix_quick_entry_cli_toggle: Only {applied}/{EXPECTED} sub-patches applied")

  if content != original:
    echo &"  [PASS] {applied}/{EXPECTED} sub-patches applied"
  else:
    echo &"  [PASS] No changes needed — already patched ({applied}/{EXPECTED})"

  return content

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_quick_entry_cli_toggle <file>"
    quit(1)
  let file = paramStr(1)
  echo "=== Patch: fix_quick_entry_cli_toggle ==="
  echo &"  Target: {file}"
  let input = readFile(file)
  let output = apply(input)
  if output != input:
    writeFile(file, output)
  echo "  [PASS]"
