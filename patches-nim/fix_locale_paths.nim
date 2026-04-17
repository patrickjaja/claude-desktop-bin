# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
# Nim port of fix_locale_paths.py.

import std/[os, strformat, strutils]
import regex

const
  OldResourcePath = "process.resourcesPath"
  NewResourcePath = """(require("path").dirname(require("electron").app.getAppPath())+"/locales")"""

proc countOccurrences(s, sub: string): int =
  var i = 0
  while true:
    let k = s.find(sub, i)
    if k < 0: break
    inc result
    i = k + sub.len

proc apply*(input: string): string =
  var content = input
  var failed = false

  let count1 = countOccurrences(content, OldResourcePath)
  if count1 >= 1:
    content = content.replace(OldResourcePath, NewResourcePath)
    echo &"  [OK] process.resourcesPath: {count1} match(es)"
  else:
    echo "  [FAIL] process.resourcesPath: 0 matches, expected >= 1"
    failed = true

  let hardcoded = re2"""/usr/lib/electron\d+/resources"""
  var count2 = 0
  content = content.replace(hardcoded, proc (m: RegexMatch2, s: string): string =
    inc count2
    NewResourcePath
  )
  if count2 > 0:
    echo &"  [OK] hardcoded electron paths: {count2} match(es)"
  else:
    echo "  [INFO] hardcoded electron paths: 0 matches (optional)"

  if failed:
    echo "  [FAIL] Required patterns did not match"
    raise newException(ValueError, "fix_locale_paths: required patterns not matched")

  result = content

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_locale_paths <path_to_index.js>"
    quit(1)
  let file = paramStr(1)
  echo "=== Patch: fix_locale_paths ==="
  echo &"  Target: {file}"
  let input = readFile(file)
  let output = apply(input)
  if output != input:
    writeFile(file, output)
    echo "  [PASS] All required patterns matched and applied"
  else:
    echo "  [WARN] No changes made (patterns may have already been applied)"

  # Also patch index.pre.js if it exists
  let preJs = parentDir(file) / "index.pre.js"
  if fileExists(preJs):
    let preContent = readFile(preJs)
    let preCount = countOccurrences(preContent, OldResourcePath)
    if preCount > 0:
      let newPre = preContent.replace(OldResourcePath, NewResourcePath)
      writeFile(preJs, newPre)
      echo &"  [OK] index.pre.js: process.resourcesPath patched ({preCount} match)"
    else:
      echo "  [INFO] index.pre.js: no process.resourcesPath (already patched or absent)"
