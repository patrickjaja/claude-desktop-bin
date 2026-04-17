# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
# Nim port of fix_computer_use_tcc.py

import std/[os, strformat]
import regex

proc buildStubHandlersJs(eipcPrefix: string): string =
  result = "if(process.platform===\"linux\"){" &
    "const _ipc=require(\"electron\").ipcMain;" &
    "const _P=\"" & eipcPrefix & "\";" &
    "_ipc.handle(_P+\"getState\",()=>({accessibility:\"not_applicable\",screenRecording:\"not_applicable\"}));" &
    "_ipc.handle(_P+\"requestAccessibility\",()=>{});" &
    "_ipc.handle(_P+\"requestScreenRecording\",()=>{});" &
    "_ipc.handle(_P+\"openSystemSettings\",()=>{});" &
    "_ipc.handle(_P+\"getCurrentSessionGrants\",()=>[]);" &
    "_ipc.handle(_P+\"revokeGrant\",()=>{});" &
    "}"

proc extractEipcUuid(content: string): string =
  let p = re2"\$eipc_message\$_([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})"
  var m: RegexMatch2
  if content.find(p, m):
    result = content[m.group(0)]
  else:
    result = ""

proc apply*(input: string, filepath: string = ""): string =
  var content = input
  let original = input

  var uuid = extractEipcUuid(content)
  if uuid.len == 0 and filepath.len > 0:
    # Fallback: check mainView.js
    let mainView = filepath.parentDir() / "mainView.js"
    if fileExists(mainView):
      uuid = extractEipcUuid(readFile(mainView))
  if uuid.len == 0:
    echo "  [FAIL] Could not extract eipc UUID from source files"
    raise newException(ValueError, "fix_computer_use_tcc: could not extract eipc UUID")

  let eipcPrefix = &"$eipc_message$_{uuid}_$_claude.web_$_ComputerUseTcc_$_"
  echo &"  [OK] Extracted eipc UUID: {uuid}"

  let stubJs = buildStubHandlersJs(eipcPrefix)

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
    echo &"  [OK] ComputerUseTcc stub handlers: injected ({count} match)"
  else:
    echo "  [FAIL] app.on(\"ready\") pattern: 0 matches"
    raise newException(ValueError, "fix_computer_use_tcc: app.on(ready) not found")

  result = content

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_computer_use_tcc <file>"
    quit(1)
  let file = paramStr(1)
  echo "=== Patch: fix_computer_use_tcc ==="
  echo &"  Target: {file}"
  let input = readFile(file)
  let output = apply(input, file)
  if output != input:
    writeFile(file, output)
    echo "  [PASS] ComputerUseTcc handlers registered for Linux"
  else:
    echo "  [WARN] No changes made"
