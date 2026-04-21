# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
# Add safety-net error handler for ClaudeVM and LocalAgentModeSessions IPC on Linux.
# Suppresses "ClaudeVM" / "LocalAgentModeSessions" uncaught exceptions.

import std/[os, strformat, strutils]
import regex

proc replaceFirst(content: var string, pattern: Regex2, subFn: proc(m: RegexMatch2, s: string): string): int =
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

proc apply*(input: string): string =
  result = input
  var patchesApplied = 0

  # Primary pattern: async ready handler
  let appReadyPat = re2"([\w$]+)\.app\.on\(""ready"",async\(\)=>\{"

  var count = result.replaceFirst(appReadyPat, proc(m: RegexMatch2, s: string): string =
    let electronVar = s[m.group(0)]
    electronVar & ".app.on(\"ready\",async()=>{if(process.platform===\"linux\"){process.on(\"uncaughtException\",(e)=>{if(e.message&&(e.message.includes(\"ClaudeVM\")||e.message.includes(\"LocalAgentModeSessions\"))){console.log(\"[LinuxPatch] Suppressing unsupported feature error:\",e.message);return}throw e})};"
  )
  if count >= 1:
    echo &"  [OK] App error handler: {count} match(es)"
    patchesApplied += 1
  else:
    # Try alternative pattern (non-async)
    let appReadyPatAlt = re2"([\w$]+)\.app\.on\(""ready"",\(\)=>\{"

    var countAlt = result.replaceFirst(appReadyPatAlt, proc(m: RegexMatch2, s: string): string =
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

  if result != input:
    # Verify brace balance
    let originalDelta = input.count('{') - input.count('}')
    let patchedDelta = result.count('{') - result.count('}')
    if originalDelta != patchedDelta:
      let diff = patchedDelta - originalDelta
      raise newException(ValueError, &"fix_vm_session_handlers: Patch introduced brace imbalance: {diff:+} unmatched braces")

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_vm_session_handlers <file>"
    quit(1)
  let file = paramStr(1)
  echo "=== Patch: fix_vm_session_handlers ==="
  echo &"  Target: {file}"
  if not fileExists(file):
    echo &"  [FAIL] File not found: {file}"
    quit(1)
  let input = readFile(file)
  let output = apply(input)
  if output == input:
    echo "  [WARN] No changes made (patterns may have already been applied)"
  else:
    writeFile(file, output)
    echo "  [PASS] 1 patches applied"
