# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
# Enable `claude-desktop --toggle-quick-entry` CLI trigger for Quick Entry.
# Four sub-patches (A and C share a counter slot):
#   A - capture the Quick Entry show handler into globalThis.__ceQuickEntryShow
#       with a 900ms debounce guard (prevents GNOME double-firing second-instance)
#   B - prepend argv check to second-instance handler (warm-start hotkey path)
#   C - schedule first-instance check after 500ms (cold-start: app just launched
#       with --toggle-quick-entry; gives Electron enough time to initialise)
#   D - create Unix domain socket at /run/user/<uid>/claude-desktop-qe.sock
#       so claude-desktop-toggle can trigger Quick Entry in ~5-25ms instead of
#       ~300ms (no Electron process spawn for every keypress)

import std/[os, strformat, strutils]
import regex

const TRIGGER_FLAG = "--toggle-quick-entry"
const HANDLER_GLOBAL = "__ceQuickEntryShow"
const EXPECTED = 3

proc apply*(input: string): string =
  result = input
  var applied = 0

  # Sub-patch A + C: capture handler into globalThis.__ceQuickEntryShow
  if HANDLER_GLOBAL in result:
    echo &"  [INFO] {HANDLER_GLOBAL} already present -- sub-patch A/C skipped"
    applied += 2
  else:
    let patA = re2"([\w$]+)\(([\w$]+)\.QUICK_ENTRY,(\(\)=>\{[\w$]+&&![\w$]+\.isDestroyed\(\)&&[\w$]+\.isFullScreen\(\)\?\([\w$]+\.focus\(\),[\w$]+\(\)\):[\w$]+\(\)\})\)"

    var countA = 0
    var resultStr = ""
    var lastEnd = 0
    for m in result.findAll(patA):
      if countA == 0:
        let bounds = m.boundaries
        resultStr &= result[lastEnd ..< bounds.a]

        let regFn = result[m.group(0)]
        let enumVar = result[m.group(1)]
        let arrow = result[m.group(2)]

        # Verify arrow shape
        assert arrow.startsWith("()=>{") and arrow.endsWith("}"), "unexpected arrow shape: " & arrow

        let body = arrow[len("()=>{") ..< arrow.len - 1]

        # A: register with assignment to globalThis AND a debounce guard.
        # 900ms debounce: guards against GNOME's duplicate second-instance delivery
        # (issue #38, double-fires within 1-5ms). Even though the socket trigger
        # (sub-patch D) bypasses second-instance entirely while the app is running,
        # the 900ms guard still protects cold-start CLI opens where second-instance
        # is the only path (socket not yet up).
        let arrowWrapped = "()=>{var __t=Date.now();if(globalThis.__ceQEInvokedAt&&__t-globalThis.__ceQEInvokedAt<900)return;globalThis.__ceQEInvokedAt=__t;" & body & "}"
        let assign = "globalThis." & HANDLER_GLOBAL & "=" & arrowWrapped

        # C: schedule first-instance check
        let firstInstance =
          ",setTimeout(()=>{" &
          "try{if(Array.isArray(process.argv)&&process.argv.includes(\"" &
          TRIGGER_FLAG &
          "\")&&globalThis." &
          HANDLER_GLOBAL &
          ")globalThis." &
          HANDLER_GLOBAL &
          "()}catch(e){}" &
          "},500)"

        # D: Unix domain socket trigger -- fast hotkey path on Linux.
        #
        # Problem: `claude-desktop --toggle-quick-entry` spawns a full Electron process
        # just to IPC to the running instance (~300 ms cold overhead per keypress).
        #
        # Solution: on startup the app creates a Unix domain socket at
        # /run/user/<uid>/claude-desktop-qe.sock. Any connection toggles Quick Entry in
        # ~5-25 ms (no process spawn). The packaged `claude-desktop-toggle` script tries
        # socat (~2 ms) or python3 (~25 ms) first, then falls back to the old Electron
        # path when the app is not running.
        #
        # Hotkey command: claude-desktop-toggle   (installed in /usr/bin by all packages)
        #
        # Falls back gracefully: if /run/user/ is unavailable the try/catch swallows
        # the error and the old --toggle-quick-entry path continues to work.
        let socketTrigger =
          ",(()=>{" &
          "if(process.platform!==\"linux\")return;" &
          "try{" &
          "const _qeS=`/run/user/${process.getuid()}/claude-desktop-qe.sock`;" &
          "try{require(\"fs\").unlinkSync(_qeS)}catch(e){}" &
          "require(\"net\").createServer(c=>{" &
          "c.on(\"error\",()=>{});" &
          "c.end();" &
          "try{if(globalThis." & HANDLER_GLOBAL & ")globalThis." & HANDLER_GLOBAL & "()}catch(e){}" &
          "}).listen(_qeS);" &
          "if(!globalThis.__qeTriggerLogged){globalThis.__qeTriggerLogged=true;" &
          "console.log(\"[quick-entry] socket trigger ready: \"+_qeS)}" &
          "}catch(e){}" &
          "})()"

        resultStr &= regFn & "(" & enumVar & ".QUICK_ENTRY," & assign & ")" & firstInstance & socketTrigger
        lastEnd = bounds.b + 1
        inc countA
        break

    if countA == 1:
      resultStr &= result[lastEnd .. ^1]
      result = resultStr
      echo "  [OK] sub-patch A (handler capture) + C (first-instance schedule) applied"
      applied += 2
    elif countA > 1:
      raise newException(ValueError, &"fix_quick_entry_cli_toggle: sub-patch A matched {countA} times (expected 1)")
    else:
      raise newException(ValueError, "fix_quick_entry_cli_toggle: sub-patch A did not match QUICK_ENTRY handler registration")

  # Sub-patch B: prepend argv check to second-instance handler
  let bMarker = "\"" & TRIGGER_FLAG & "\")){try{globalThis."
  if bMarker in result:
    echo "  [INFO] sub-patch B already applied -- skipped"
    applied += 1
  else:
    let patB = re2"(\.on\(""second-instance"",\()([\w$]+),([\w$]+),([\w$]+)(\)=>\{)"

    var countB = 0
    var resultStr2 = ""
    var lastEnd2 = 0
    for m in result.findAll(patB):
      if countB == 0:
        let bounds = m.boundaries
        resultStr2 &= result[lastEnd2 ..< bounds.a]

        let head = result[m.group(0)]
        let evt = result[m.group(1)]
        let argv = result[m.group(2)]
        let cwd = result[m.group(3)]
        let tail = result[m.group(4)]

        let check =
          "if(Array.isArray(" & argv & ")&&" & argv &
          ".includes(\"" & TRIGGER_FLAG & "\"))" &
          "{try{globalThis." & HANDLER_GLOBAL &
          "&&globalThis." & HANDLER_GLOBAL &
          "()}catch(e){}return}"

        resultStr2 &= head & evt & "," & argv & "," & cwd & tail & check
        lastEnd2 = bounds.b + 1
        inc countB
        break

    if countB == 1:
      resultStr2 &= result[lastEnd2 .. ^1]
      result = resultStr2
      echo "  [OK] sub-patch B (second-instance argv check) applied"
      applied += 1
    elif countB > 1:
      raise newException(ValueError, &"fix_quick_entry_cli_toggle: sub-patch B matched {countB} times (expected 1)")
    else:
      raise newException(ValueError, "fix_quick_entry_cli_toggle: sub-patch B did not match .on(\"second-instance\", ...) handler")

  if applied < EXPECTED:
    raise newException(ValueError, &"fix_quick_entry_cli_toggle: Only {applied}/{EXPECTED} sub-patches applied")

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_quick_entry_cli_toggle <file>"
    quit(1)
  let file = paramStr(1)
  echo "=== Patch: fix_quick_entry_cli_toggle ==="
  echo &"  Target: {file}"
  if not fileExists(file):
    echo &"  [FAIL] File not found: {file}"
    quit(1)
  let input = readFile(file)
  let output = apply(input)
  if output != input:
    writeFile(file, output)
    echo &"  [PASS] {EXPECTED}/{EXPECTED} sub-patches applied"
  else:
    echo &"  [PASS] No changes needed -- already patched ({EXPECTED}/{EXPECTED})"
