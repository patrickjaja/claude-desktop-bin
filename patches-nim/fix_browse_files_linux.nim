# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
# Nim port of fix_browse_files_linux.py

import std/[os, strformat, strutils]

proc apply*(input: string): string =
  let needle = "process.platform===\"darwin\"?[\"openFile\",\"openDirectory\",\"multiSelections\"]:[\"openFile\",\"multiSelections\"]"
  let patched = "process.platform===\"darwin\"||process.platform===\"linux\"?[\"openFile\",\"openDirectory\",\"multiSelections\"]:[\"openFile\",\"multiSelections\"]"

  let count = input.count(needle)
  if count == 0:
    raise newException(ValueError, "fix_browse_files_linux: pattern not found (0 matches)")
  result = input.replace(needle, patched)
  echo &"  [OK] browseFiles openDirectory: {count} match(es)"

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_browse_files_linux <file>"
    quit(1)
  let file = paramStr(1)
  echo "=== Patch: fix_browse_files_linux ==="
  echo &"  Target: {file}"
  let input = readFile(file)
  let output = apply(input)
  if output != input:
    writeFile(file, output)
    echo "  [PASS] Browse files dialog patched successfully"
  else:
    echo "  [WARN] No changes made"
