# @patch-target: app.asar.contents/.vite/build/index.pre.js
# @patch-type: nim
#
# Patch locale file paths in the bootstrap file (index.pre.js).
# Same logic as fix_locale_paths.nim but for the pre-loader that runs first.

import std/[os, strutils]
import regex

proc apply*(input: string): string =
  let oldResourcePath = "process.resourcesPath"
  let newResourcePath =
    """(require("path").dirname(require("electron").app.getAppPath())+"/locales")"""

  let count = input.count(oldResourcePath)
  if count >= 1:
    result = input.replace(oldResourcePath, newResourcePath)
    echo "  [OK] process.resourcesPath: " & $count & " match(es)"
  else:
    echo "  [FAIL] process.resourcesPath: 0 matches, expected >= 1"
    result = input
    quit(1)

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_locale_paths_pre <path_to_index.pre.js>"
    quit(1)
  let filePath = paramStr(1)
  echo "=== Patch: fix_locale_paths_pre ==="
  echo "  Target: " & filePath
  if not fileExists(filePath):
    echo "  [FAIL] File not found: " & filePath
    quit(1)
  let input = readFile(filePath)
  let output = apply(input)

  if output != input:
    writeFile(filePath, output)
    echo "  [PASS] All required patterns matched and applied"
  else:
    echo "  [WARN] No changes made (patterns may have already been applied)"
