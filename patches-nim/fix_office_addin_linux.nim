# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
# Nim port of fix_office_addin_linux.py.

import std/[os, strformat, strutils]
import regex

const ExpectedPatches = 3

proc countChar(s: string, c: char): int =
  for x in s: (if x == c: inc result)

proc apply*(input: string): string =
  var content = input
  var patchesApplied = 0

  # Patch A: MCP server isEnabled gate
  let alreadyA = re2"""&&\([\w$]+\|\|[\w$]+\|\|process\.platform==="linux"\)&&[\w$]+\("louderPenguinEnabled"\)"""
  var hasAlreadyA = false
  for _ in content.findAll(alreadyA):
    hasAlreadyA = true
    break
  if hasAlreadyA:
    echo "  [OK] MCP server isEnabled: already patched (skipped)"
    inc patchesApplied
  else:
    let patternA = re2"""(&&\()([\w$]+\|\|[\w$]+)(\)&&[\w$]+\("louderPenguinEnabled"\))"""
    let counter = new int
    counter[] = 0
    content = content.replace(patternA, proc (m: RegexMatch2, s: string): string =
      inc counter[]
      s[m.group(0)] & s[m.group(1)] & "||process.platform===\"linux\"" & s[m.group(2)]
    )
    if counter[] >= 1:
      echo &"  [OK] MCP server isEnabled: added Linux ({counter[]} match)"
      inc patchesApplied
    else:
      echo "  [FAIL] MCP server isEnabled: pattern not found"

  # Patch B: Init block gate
  let alreadyB = re2"""\}\);\([\w$]+\|\|[\w$]+\|\|process\.platform==="linux"\)&&[\w$]+\("louderPenguinEnabled"\)&&\("""
  var hasAlreadyB = false
  for _ in content.findAll(alreadyB):
    hasAlreadyB = true
    break
  if hasAlreadyB:
    echo "  [OK] Init block: already patched (skipped)"
    inc patchesApplied
  else:
    let patternB = re2"""(\}\);\()([\w$]+\|\|[\w$]+)(\)&&[\w$]+\("louderPenguinEnabled"\)&&\()"""
    let counter = new int
    counter[] = 0
    content = content.replace(patternB, proc (m: RegexMatch2, s: string): string =
      inc counter[]
      s[m.group(0)] & s[m.group(1)] & "||process.platform===\"linux\"" & s[m.group(2)]
    )
    if counter[] >= 1:
      echo &"  [OK] Init block: added Linux ({counter[]} match)"
      inc patchesApplied
    else:
      echo "  [FAIL] Init block: pattern not found"

  # Patch C: Connected file detection gate
  let alreadyC = re2"""\([\w$]+\|\|[\w$]+\|\|process\.platform==="linux"\)&&await [\w$]+\([\w$]+\.app,[\w$]+\.document\)"""
  var hasAlreadyC = false
  for _ in content.findAll(alreadyC):
    hasAlreadyC = true
    break
  if hasAlreadyC:
    echo "  [OK] Connected file detection: already patched (skipped)"
    inc patchesApplied
  else:
    let patternC = re2"""(\()([\w$]+\|\|[\w$]+)(\)&&await [\w$]+\([\w$]+\.app,[\w$]+\.document\))"""
    let counter = new int
    counter[] = 0
    content = content.replace(patternC, proc (m: RegexMatch2, s: string): string =
      inc counter[]
      s[m.group(0)] & s[m.group(1)] & "||process.platform===\"linux\"" & s[m.group(2)]
    )
    if counter[] >= 1:
      echo &"  [OK] Connected file detection: added Linux ({counter[]} match)"
      inc patchesApplied
    else:
      echo "  [FAIL] Connected file detection: pattern not found"

  if patchesApplied < ExpectedPatches:
    echo &"  [FAIL] Only {patchesApplied}/{ExpectedPatches} patches applied — check [WARN]/[FAIL] messages above"
    raise newException(ValueError, "fix_office_addin_linux: patches not fully applied")

  if content == input:
    echo &"  [OK] All {patchesApplied} patches already applied (no changes needed)"
    return content

  # Brace balance check
  let origDelta = countChar(input, '{') - countChar(input, '}')
  let newDelta = countChar(content, '{') - countChar(content, '}')
  if origDelta != newDelta:
    let diff = newDelta - origDelta
    echo &"  [FAIL] Patch introduced brace imbalance: {diff:+d} unmatched braces"
    raise newException(ValueError, "fix_office_addin_linux: brace imbalance")

  result = content

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_office_addin_linux <path_to_index.js>"
    quit(1)
  let file = paramStr(1)
  echo "=== Patch: fix_office_addin_linux ==="
  echo &"  Target: {file}"
  let input = readFile(file)
  let output = apply(input)
  if output != input:
    writeFile(file, output)
    # Count applied from re-applying header trail — use simpler message:
    echo "  [PASS] patches applied"
