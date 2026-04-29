# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
#
# A: Force CCD mode on Linux (no Cowork VM available).
# B: CLI stores personal plugins as scope="project"+projectPath=$HOME;
#    promote those to scope="user" so the web UI shows them under
#    "Personal Plugins" instead of the current project header.

import std/[os, strformat, strutils]
import std/nre

const EXPECTED_PATCHES = 2

proc apply*(input: string): string =
  result = input
  var patchesApplied = 0

  # A: CCD/Cowork gate
  if result.contains(
    re"""function [\w$]+\([\w$]+\)\{return process\.platform==="linux"\|\|"""
  ):
    echo "  [SKIP] A already patched"
    inc patchesApplied
  else:
    let m = result.find(
      re"""function ([\w$]+)\(([\w$]+)\)\{return\((\2)==null\?void 0:\3\.mode\)==="ccd"\}"""
    )
    if m.isSome:
      let c = m.get.captures
      result =
        result[0 ..< m.get.matchBounds.a] & "function " & c[0] & "(" & c[1] &
        "){return process.platform===\"linux\"||(" & c[1] & "==null?void 0:" & c[1] &
        ".mode)===\"ccd\"}" & result[m.get.matchBounds.b + 1 .. ^1]
      echo "  [OK] A CCD gate (1 match)"
      inc patchesApplied
    else:
      echo "  [FAIL] A CCD gate: 0 matches"

  # B: scope normalization in getAllLocalPluginsWithResolver
  if result.contains(
    re"""if\([\w$]+\.scope===\"user\"\|\|[\w$]+\.scope===\"project\"\&\&[\w$]+\.projectPath"""
  ):
    echo "  [SKIP] B already patched"
    inc patchesApplied
  else:
    let m = result.find(
      re"""if\(([\w$]+)\.scope===\"user\"\)\{([\w$]+)\.push\(this\.entryToPluginInfo\(([\w$]+),\1,([\w$]+),([\w$]+)\)\);continue\}"""
    )
    if m.isSome:
      let c = m.get.captures
      let (e, s, o, n, i) = (c[0], c[1], c[2], c[3], c[4])
      let homedir =
        e & ".scope===\"project\"&&" & e & ".projectPath&&" &
        "process.env.HOME&&require(\"path\").normalize(" & e &
        ".projectPath)===require(\"path\").normalize(process.env.HOME)"
      result =
        result[0 ..< m.get.matchBounds.a] & "if(" & e & ".scope===\"user\"||" & homedir &
        "){" & s & ".push(this.entryToPluginInfo(" & o & ",{..." & e &
        ",scope:\"user\"}," & n & "," & i & "));continue}" &
        result[m.get.matchBounds.b + 1 .. ^1]
      echo "  [OK] B scope normalization (1 match)"
      inc patchesApplied
    else:
      echo "  [FAIL] B scope normalization: 0 matches"

  if patchesApplied < EXPECTED_PATCHES:
    echo &"  [FAIL] Only {patchesApplied}/{EXPECTED_PATCHES} sub-patches applied"
    quit(1)

  let originalDelta = input.count('{') - input.count('}')
  let patchedDelta = result.count('{') - result.count('}')
  if originalDelta != patchedDelta:
    echo &"  [FAIL] Brace balance changed: {originalDelta} -> {patchedDelta}"
    quit(1)

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_marketplace_linux <path_to_index.js>"
    quit(1)
  let filePath = paramStr(1)
  echo "=== Patch: fix_marketplace_linux ==="
  echo "  Target: " & filePath
  if not fileExists(filePath):
    echo "  [FAIL] File not found: " & filePath
    quit(1)
  let input = readFile(filePath)
  let output = apply(input)
  if output != input:
    writeFile(filePath, output)
  echo "  [PASS] Marketplace Linux patch applied"
