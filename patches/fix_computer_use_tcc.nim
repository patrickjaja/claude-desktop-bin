# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
# Register stub IPC handlers for ComputerUseTcc on Linux.
# Prevents "No handler registered" errors for accessibility/screen recording.

import std/[os, strformat, strutils]
import regex

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

proc buildStubHandlersJs(eipcPrefix: string): string =
  result =
    "if(process.platform===\"linux\"){" & "const _ipc=require(\"electron\").ipcMain;" &
    "const _P=\"" & eipcPrefix & "\";" &
    "_ipc.handle(_P+\"getState\",()=>({accessibility:\"not_applicable\",screenRecording:\"not_applicable\"}));" &
    "_ipc.handle(_P+\"requestAccessibility\",()=>{});" &
    "_ipc.handle(_P+\"requestScreenRecording\",()=>{});" &
    "_ipc.handle(_P+\"openSystemSettings\",()=>{});" &
    "_ipc.handle(_P+\"getCurrentSessionGrants\",()=>[]);" &
    "_ipc.handle(_P+\"revokeGrant\",()=>{});" & "}"

proc apply*(input: string): string =
  result = input

  var uuid = extractEipcUuid(result)
  if uuid == "":
    raise newException(
      ValueError, "fix_computer_use_tcc: Could not extract eipc UUID from source files"
    )

  let eipcPrefix = "$eipc_message$_" & uuid & "_$_claude.web_$_ComputerUseTcc_$_"
  echo &"  [OK] Extracted eipc UUID: {uuid}"

  let stubJs = buildStubHandlersJs(eipcPrefix)

  let pattern = re2"(app\.on\(""ready"",async\(\)=>\{)"
  var count = result.replaceFirst(
    pattern,
    proc(m: RegexMatch2, s: string): string =
      s[m.group(0)] & stubJs,
  )
  if count >= 1:
    echo &"  [OK] ComputerUseTcc stub handlers: injected ({count} match)"
  else:
    echo "  [FAIL] app.on(\"ready\") pattern: 0 matches"
    raise newException(
      ValueError, "fix_computer_use_tcc: app.on(\"ready\") pattern not found"
    )

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_computer_use_tcc <file>"
    quit(1)
  let file = paramStr(1)
  echo "=== Patch: fix_computer_use_tcc ==="
  echo &"  Target: {file}"
  if not fileExists(file):
    echo &"  [FAIL] File not found: {file}"
    quit(1)
  let input = readFile(file)
  let output = apply(input)
  if output != input:
    writeFile(file, output)
    echo "  [PASS] ComputerUseTcc handlers registered for Linux"
  else:
    echo "  [WARN] No changes made"
