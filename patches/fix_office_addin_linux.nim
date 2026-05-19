# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
# Enable Office Addin (louderPenguin) feature on Linux.
#
# History: v1.1.8308-v1.7196.1 had 3 patches (A: MCP server isEnabled,
# B: init block gate, C: connected file detection). In v1.8089.0 the
# upstream refactored the office-addin feature: the platform+featureFlag
# gates on the MCP server registration (old A) and init block (old B) were
# removed - the init code now runs unconditionally and the feature flag
# hi("louderPenguinEnabled") is checked independently of platform.
#
# Only Patch C (connected file detection) still has a platform gate:
#   (DARWIN_VAR||WIN32_VAR)&&await FUNC(e.app,e.document)
# We add ||process.platform==="linux" to that gate.

import std/[os, strformat, strutils]
import regex

const EXPECTED_PATCHES = 1

proc apply*(input: string): string =
  result = input
  var patchesApplied = 0

  # Patch C: Connected file detection gate
  let alreadyCPat =
    re2"""\([\w$]+\|\|[\w$]+\|\|process\.platform==="linux"\)&&await [\w$]+\([\w$]+\.app,[\w$]+\.document\)"""
  var alreadyC = false
  for m in result.findAll(alreadyCPat):
    alreadyC = true
    break

  if alreadyC:
    echo "  [OK] Connected file detection: already patched (skipped)"
    patchesApplied += 1
  else:
    let patternC =
      re2"""(\()([\w$]+\|\|[\w$]+)(\)&&await [\w$]+\([\w$]+\.app,[\w$]+\.document\))"""
    var countC = 0
    result = result.replace(
      patternC,
      proc(m: RegexMatch2, s: string): string =
        inc countC
        s[m.group(0)] & s[m.group(1)] & """||process.platform==="linux"""" &
          s[m.group(2)],
    )
    if countC >= 1:
      echo &"  [OK] Connected file detection: added Linux ({countC} match)"
      patchesApplied += 1
    else:
      echo "  [FAIL] Connected file detection: pattern not found"

  if patchesApplied < EXPECTED_PATCHES:
    raise newException(
      ValueError,
      &"fix_office_addin_linux: Only {patchesApplied}/{EXPECTED_PATCHES} patches applied",
    )

  if result != input:
    let originalDelta = input.count('{') - input.count('}')
    let patchedDelta = result.count('{') - result.count('}')
    if originalDelta != patchedDelta:
      let diff = patchedDelta - originalDelta
      raise newException(
        ValueError,
        &"fix_office_addin_linux: Patch introduced brace imbalance: {diff:+} unmatched braces",
      )

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
