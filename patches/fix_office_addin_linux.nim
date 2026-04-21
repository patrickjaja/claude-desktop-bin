# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
# Enable Office Addin (louderPenguin) feature on Linux.
# Three patches: MCP server isEnabled, init block gate, connected file detection.

import std/[os, strformat, strutils]
import regex

const EXPECTED_PATCHES = 3

proc apply*(input: string): string =
  result = input
  var patchesApplied = 0

  # Patch A: MCP server isEnabled gate
  let alreadyAPat = re2"""&&\([\w$]+\|\|[\w$]+\|\|process\.platform==="linux"\)&&[\w$]+\("louderPenguinEnabled"\)"""
  var alreadyA = false
  for m in result.findAll(alreadyAPat):
    alreadyA = true
    break

  if alreadyA:
    echo "  [OK] MCP server isEnabled: already patched (skipped)"
    patchesApplied += 1
  else:
    let patternA = re2"""(&&\()([\w$]+\|\|[\w$]+)(\)&&[\w$]+\("louderPenguinEnabled"\))"""
    var countA = 0
    result = result.replace(patternA, proc(m: RegexMatch2, s: string): string =
      inc countA
      s[m.group(0)] & s[m.group(1)] & """||process.platform==="linux"""" & s[m.group(2)]
    )
    if countA >= 1:
      echo &"  [OK] MCP server isEnabled: added Linux ({countA} match)"
      patchesApplied += 1
    else:
      echo "  [FAIL] MCP server isEnabled: pattern not found"

  # Patch B: Init block gate
  let alreadyBPat = re2"""\}\);\([\w$]+\|\|[\w$]+\|\|process\.platform==="linux"\)&&[\w$]+\("louderPenguinEnabled"\)&&\("""
  var alreadyB = false
  for m in result.findAll(alreadyBPat):
    alreadyB = true
    break

  if alreadyB:
    echo "  [OK] Init block: already patched (skipped)"
    patchesApplied += 1
  else:
    let patternB = re2"""(\}\);\()([\w$]+\|\|[\w$]+)(\)&&[\w$]+\("louderPenguinEnabled"\)&&\()"""
    var countB = 0
    result = result.replace(patternB, proc(m: RegexMatch2, s: string): string =
      inc countB
      s[m.group(0)] & s[m.group(1)] & """||process.platform==="linux"""" & s[m.group(2)]
    )
    if countB >= 1:
      echo &"  [OK] Init block: added Linux ({countB} match)"
      patchesApplied += 1
    else:
      echo "  [FAIL] Init block: pattern not found"

  # Patch C: Connected file detection gate
  let alreadyCPat = re2"""\([\w$]+\|\|[\w$]+\|\|process\.platform==="linux"\)&&await [\w$]+\([\w$]+\.app,[\w$]+\.document\)"""
  var alreadyC = false
  for m in result.findAll(alreadyCPat):
    alreadyC = true
    break

  if alreadyC:
    echo "  [OK] Connected file detection: already patched (skipped)"
    patchesApplied += 1
  else:
    let patternC = re2"""(\()([\w$]+\|\|[\w$]+)(\)&&await [\w$]+\([\w$]+\.app,[\w$]+\.document\))"""
    var countC = 0
    result = result.replace(patternC, proc(m: RegexMatch2, s: string): string =
      inc countC
      s[m.group(0)] & s[m.group(1)] & """||process.platform==="linux"""" & s[m.group(2)]
    )
    if countC >= 1:
      echo &"  [OK] Connected file detection: added Linux ({countC} match)"
      patchesApplied += 1
    else:
      echo "  [FAIL] Connected file detection: pattern not found"

  if patchesApplied < EXPECTED_PATCHES:
    raise newException(ValueError, &"fix_office_addin_linux: Only {patchesApplied}/{EXPECTED_PATCHES} patches applied")

  if result != input:
    let originalDelta = input.count('{') - input.count('}')
    let patchedDelta = result.count('{') - result.count('}')
    if originalDelta != patchedDelta:
      let diff = patchedDelta - originalDelta
      raise newException(ValueError, &"fix_office_addin_linux: Patch introduced brace imbalance: {diff:+} unmatched braces")

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_office_addin_linux <file>"
    quit(1)
  let file = paramStr(1)
  echo "=== Patch: fix_office_addin_linux ==="
  echo &"  Target: {file}"
  if not fileExists(file):
    echo &"  [FAIL] File not found: {file}"
    quit(1)
  let input = readFile(file)
  let output = apply(input)
  if output == input:
    echo &"  [OK] All {EXPECTED_PATCHES} patches already applied (no changes needed)"
  else:
    writeFile(file, output)
    echo &"  [PASS] {EXPECTED_PATCHES} patches applied"
