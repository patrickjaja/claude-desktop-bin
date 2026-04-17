# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
# Nim port of fix_vm_session_handlers.py

import std/[os, strformat]
import regex

proc apply*(input: string): string =
  var content = input
  let original = input
  var patchesApplied = 0

  # Try async pattern first
  let appReadyPat = re2"""([\w$]+)\.app\.on\("ready",async\(\)=>\{"""
  var count = 0
  var done = false
  content = content.replace(appReadyPat, proc (m: RegexMatch2, s: string): string =
    if done:
      return s[m.boundaries]
    inc count
    done = true
    let electronVar = s[m.group(0)]
    electronVar & ".app.on(\"ready\",async()=>{if(process.platform===\"linux\"){process.on(\"uncaughtException\",(e)=>{if(e.message&&(e.message.includes(\"ClaudeVM\")||e.message.includes(\"LocalAgentModeSessions\"))){console.log(\"[LinuxPatch] Suppressing unsupported feature error:\",e.message);return}throw e})};"
  )

  if count >= 1:
    echo &"  [OK] App error handler: {count} match(es)"
    patchesApplied += 1
  else:
    # Try alternative non-async pattern
    let appReadyPatAlt = re2"""([\w$]+)\.app\.on\("ready",\(\)=>\{"""
    var countAlt = 0
    var doneAlt = false
    content = content.replace(appReadyPatAlt, proc (m: RegexMatch2, s: string): string =
      if doneAlt:
        return s[m.boundaries]
      inc countAlt
      doneAlt = true
      let electronVar = s[m.group(0)]
      electronVar & ".app.on(\"ready\",()=>{if(process.platform===\"linux\"){process.on(\"uncaughtException\",(e)=>{if(e.message&&(e.message.includes(\"ClaudeVM\")||e.message.includes(\"LocalAgentModeSessions\"))){console.log(\"[LinuxPatch] Suppressing unsupported feature error:\",e.message);return}throw e})};"
    )
    if countAlt >= 1:
      echo &"  [OK] App error handler (alt): {countAlt} match(es)"
      patchesApplied += 1
    else:
      echo "  [WARN] App ready pattern not found"

  if patchesApplied == 0:
    raise newException(ValueError, "fix_vm_session_handlers: No patches could be applied")

  if content == original:
    echo "  [WARN] No changes made (patterns may have already been applied)"
    return content

  # Brace balance verification
  var origOpen = 0
  var origClose = 0
  var newOpen = 0
  var newClose = 0
  for c in original:
    if c == '{': inc origOpen
    elif c == '}': inc origClose
  for c in content:
    if c == '{': inc newOpen
    elif c == '}': inc newClose
  let originalDelta = origOpen - origClose
  let patchedDelta = newOpen - newClose
  if originalDelta != patchedDelta:
    let diff = patchedDelta - originalDelta
    raise newException(ValueError, &"fix_vm_session_handlers: Patch introduced brace imbalance: {diff:+d} unmatched braces")

  echo &"  [PASS] {patchesApplied} patches applied"
  return content

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_vm_session_handlers <file>"
    quit(1)
  let file = paramStr(1)
  echo "=== Patch: fix_vm_session_handlers ==="
  echo &"  Target: {file}"
  let input = readFile(file)
  let output = apply(input)
  if output != input:
    writeFile(file, output)
  echo "  [PASS]"
