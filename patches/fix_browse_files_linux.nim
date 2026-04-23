# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
#
# Enable directory browsing in the browseFiles dialog on Linux.
#
# The upstream code only includes "openDirectory" in the Electron dialog properties
# when running on macOS (darwin). On Linux, the dialog is limited to "openFile" +
# "multiSelections", which prevents users from selecting directories.
#
# Electron fully supports "openDirectory" on Linux, so we add a
# process.platform==="linux" check alongside the existing darwin check.

import std/[os, strutils]
import regex

proc apply*(input: string): string =
  # Pattern: the ternary that gates openDirectory behind darwin-only
  #
  # Original: process.platform==="darwin"?["openFile","openDirectory","multiSelections"]:["openFile","multiSelections"]
  # Patched:  process.platform==="darwin"||process.platform==="linux"?["openFile","openDirectory","multiSelections"]:["openFile","multiSelections"]
  #
  # All tokens here are stable Electron/Node API names (no minified variables).
  let pattern =
    re2"""process\.platform==="darwin"\?\["openFile","openDirectory","multiSelections"\]:\["openFile","multiSelections"\]"""
  let replacement =
    """process.platform==="darwin"||process.platform==="linux"?["openFile","openDirectory","multiSelections"]:["openFile","multiSelections"]"""

  var count = 0
  result = input.replace(
    pattern,
    proc(m: RegexMatch2, s: string): string =
      inc count
      replacement,
  )
  if count == 0:
    echo "  [FAIL] browseFiles openDirectory: 0 matches"
    quit(1)
  echo "  [OK] browseFiles openDirectory: " & $count & " match(es)"

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_browse_files_linux <path_to_index.js>"
    quit(1)
  let filePath = paramStr(1)
  echo "=== Patch: fix_browse_files_linux ==="
  echo "  Target: " & filePath
  if not fileExists(filePath):
    echo "  [FAIL] File not found: " & filePath
    quit(1)
  let input = readFile(filePath)
  let output = apply(input)
  if output != input:
    writeFile(filePath, output)
    echo "  [PASS] Browse files dialog patched successfully"
  else:
    echo "  [WARN] No changes made"
