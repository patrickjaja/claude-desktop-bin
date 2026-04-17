# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
# Nim port of fix_startup_settings.py

import std/[os, strformat]
import regex

proc apply*(input: string): string =
  var content = input
  var patchesApplied = 0
  const EXPECTED_PATCHES = 2

  # Pattern 1: isStartupOnLoginEnabled
  let pat1 = re2"isStartupOnLoginEnabled\(\)\{if\(process\.env\.CLAUDE_AVOID_READING_LOGING_ITEM_SETTINGS\)return!1;"
  let replacement1 = "isStartupOnLoginEnabled(){if(process.platform===\"linux\"||process.env.CLAUDE_AVOID_READING_LOGING_ITEM_SETTINGS)return!1;"
  var count1 = 0
  content = content.replace(pat1, proc (m: RegexMatch2, s: string): string =
    inc count1
    replacement1
  )
  if count1 > 0:
    patchesApplied += count1
    echo &"  [OK] isStartupOnLoginEnabled: {count1} match(es)"
  else:
    echo "  [FAIL] isStartupOnLoginEnabled: 0 matches"

  # Pattern 2: setStartupOnLoginEnabled
  let pat2 = re2"setStartupOnLoginEnabled\(([\w$]+)\)\{([\w$]+)\.debug\("
  var count2 = 0
  content = content.replace(pat2, proc (m: RegexMatch2, s: string): string =
    inc count2
    let argVar = s[m.group(0)]
    let loggerVar = s[m.group(1)]
    "setStartupOnLoginEnabled(" & argVar & "){if(process.platform===\"linux\")return;" & loggerVar & ".debug("
  )
  if count2 > 0:
    patchesApplied += count2
    echo &"  [OK] setStartupOnLoginEnabled: {count2} match(es)"
  else:
    echo "  [INFO] setStartupOnLoginEnabled: 0 matches (optional)"

  if patchesApplied < EXPECTED_PATCHES:
    raise newException(ValueError, &"fix_startup_settings: Only {patchesApplied}/{EXPECTED_PATCHES} patches applied")

  return content

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_startup_settings <file>"
    quit(1)
  let file = paramStr(1)
  echo "=== Patch: fix_startup_settings ==="
  echo &"  Target: {file}"
  let input = readFile(file)
  let output = apply(input)
  if output != input:
    writeFile(file, output)
  echo "  [PASS]"
