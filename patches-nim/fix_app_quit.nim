# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
# Nim port of fix_app_quit.py for benchmarking.

import std/[os, strformat]
import regex

proc apply*(input: string): string =
  let pattern = re2"(clearTimeout\([\w$]+\)\})([\w$]+)&&([\w$]+)(\.app\.quit\(\))"
  var count = 0
  result = input.replace(pattern, proc (m: RegexMatch2, s: string): string =
    inc count
    let g1 = s[m.group(0)]
    let flagVar = s[m.group(1)]
    let electronVar = s[m.group(2)]
    &"{g1}if({flagVar}){{setImmediate(()=>{electronVar}.app.exit(0))}}"
  )
  if count == 0:
    raise newException(ValueError, "fix_app_quit: pattern not found")

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_app_quit <file>"
    quit(1)
  let file = paramStr(1)
  echo "=== Patch: fix_app_quit ==="
  let input = readFile(file)
  let output = apply(input)
  writeFile(file, output)
  echo "  [PASS] App quit patched successfully"
