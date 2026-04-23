# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
#
# Patch Claude Desktop locale file paths for Linux.
#
# The official Claude Desktop expects locale files in Electron's resourcesPath,
# but on Linux we need to redirect to our install location. Uses a runtime
# expression based on app.getAppPath() so it works for any install method
# (Arch package, Debian package, AppImage).

import std/[os, strutils]
import regex

proc apply*(input: string): string =
  let oldResourcePath = "process.resourcesPath"
  let newResourcePath =
    """(require("path").dirname(require("electron").app.getAppPath())+"/locales")"""

  var failed = false

  # Replace process.resourcesPath with a runtime expression
  let count1 = input.count(oldResourcePath)
  if count1 >= 1:
    result = input.replace(oldResourcePath, newResourcePath)
    echo "  [OK] process.resourcesPath: " & $count1 & " match(es)"
  else:
    echo "  [FAIL] process.resourcesPath: 0 matches, expected >= 1"
    failed = true
    result = input

  # Also replace any hardcoded electron paths (optional - may not exist)
  let electronPattern = re2"/usr/lib/electron\d+/resources"
  var count2 = 0
  result = result.replace(
    electronPattern,
    proc(m: RegexMatch2, s: string): string =
      inc count2
      newResourcePath,
  )
  if count2 > 0:
    echo "  [OK] hardcoded electron paths: " & $count2 & " match(es)"
  else:
    echo "  [INFO] hardcoded electron paths: 0 matches (optional)"

  if failed:
    echo "  [FAIL] Required patterns did not match"
    quit(1)

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_locale_paths <path_to_index.js>"
    quit(1)
  let filePath = paramStr(1)
  echo "=== Patch: fix_locale_paths ==="
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

  # Also patch index.pre.js if it exists (new in v1.2278.0 -- bootstrap file)
  let preJs = parentDir(filePath) / "index.pre.js"
  if fileExists(preJs):
    let oldResourcePathStr = "process.resourcesPath"
    let newResourcePathStr =
      """(require("path").dirname(require("electron").app.getAppPath())+"/locales")"""
    let preContent = readFile(preJs)
    let preCount = preContent.count(oldResourcePathStr)
    if preCount > 0:
      let newPreContent = preContent.replace(oldResourcePathStr, newResourcePathStr)
      writeFile(preJs, newPreContent)
      echo "  [OK] index.pre.js: process.resourcesPath patched (" & $preCount & " match)"
    else:
      echo "  [INFO] index.pre.js: no process.resourcesPath (already patched or absent)"
