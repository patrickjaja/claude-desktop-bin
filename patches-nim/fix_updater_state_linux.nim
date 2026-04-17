# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
# Nim port of fix_updater_state_linux.py

import std/[os, strformat, options]
import std/nre

proc apply*(input: string): string =
  var content = input

  # Check if already patched
  let already = re"""case"idle":return\{status:[\w$]+\.[\w$]+,version:"",versionNumber:""\}"""
  if content.find(already).isSome:
    echo "  [OK] Updater idle state: already patched (skipped)"
    return content

  let pattern = re"""(case"idle":return\{status:[\w$]+\.[\w$]+)\}"""
  let m = content.find(pattern)
  if m.isSome:
    let mm = m.get
    let replacement = mm.captures[0] & ",version:\"\",versionNumber:\"\"}"
    let s = mm.matchBounds
    content = content[0 ..< s.a] & replacement & content[s.b + 1 .. ^1]
    echo "  [OK] Updater idle state: added version/versionNumber (1 match)"
    return content
  else:
    raise newException(ValueError, "fix_updater_state_linux: Updater idle state: pattern not found")

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_updater_state_linux <file>"
    quit(1)
  let file = paramStr(1)
  echo "=== Patch: fix_updater_state_linux ==="
  echo &"  Target: {file}"
  let input = readFile(file)
  let output = apply(input)
  if output != input:
    writeFile(file, output)
  echo "  [PASS]"
