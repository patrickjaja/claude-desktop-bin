# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
# Nim port of fix_enterprise_config_linux.py.

import std/[os, strformat, strutils]
import regex

const LinuxReader = """process.platform==="linux"?(()=>{try{return JSON.parse(require("fs").readFileSync("/etc/claude-desktop/enterprise.json","utf8"))}catch(e){return{}}})():{}"""

proc applyPattern(content: string): (string, int) =
  let pattern = re2"""process\.platform==="darwin"\?([\w$]+)\(\):process\.platform==="win32"\?([\w$]+)\(\):\{\}"""
  let counter = new int
  counter[] = 0
  let outStr = content.replace(pattern, proc (m: RegexMatch2, s: string): string =
    inc counter[]
    let darwinFn = s[m.group(0)]
    let win32Fn = s[m.group(1)]
    "process.platform===\"darwin\"?" & darwinFn & "():process.platform===\"win32\"?" & win32Fn & "():" & LinuxReader
  )
  result = (outStr, counter[])

proc apply*(input: string): string =
  # Idempotency
  if "/etc/claude-desktop/enterprise.json" in input:
    echo "  [OK] Already patched (enterprise.json path found)"
    echo "  [PASS] No changes needed"
    return input

  let (content, count) = applyPattern(input)
  if count >= 1:
    echo &"  [OK] Enterprise config Linux reader: {count} match(es)"
  else:
    echo "  [FAIL] Enterprise config default case: 0 matches"
    raise newException(ValueError, "fix_enterprise_config_linux: pattern not found")

  result = content

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_enterprise_config_linux <path_to_index.js>"
    quit(1)
  let file = paramStr(1)
  echo "=== Patch: fix_enterprise_config_linux ==="
  echo &"  Target: {file}"
  let input = readFile(file)
  let output = apply(input)
  if output != input:
    writeFile(file, output)
    echo "  [PASS] Enterprise config Linux support added"

  # Also patch index.pre.js if it exists
  let preJs = parentDir(file) / "index.pre.js"
  if fileExists(preJs):
    let preContent = readFile(preJs)
    if "/etc/claude-desktop/enterprise.json" in preContent:
      echo "  [OK] index.pre.js: already patched"
    else:
      let (newPre, preCount) = applyPattern(preContent)
      if preCount >= 1:
        writeFile(preJs, newPre)
        echo &"  [OK] index.pre.js: enterprise config patched ({preCount} match)"
      else:
        echo "  [INFO] index.pre.js: no matching pattern (optional)"
