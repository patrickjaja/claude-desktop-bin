# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
# Enable Imagine/Visualize MCP server on Linux.
# Two patches: isEnabled callback and hasImagine variable.

import std/[os, strformat, strutils]
import regex

const EXPECTED_PATCHES = 2

proc replaceFirst(
    content: var string, pattern: Regex2, subFn: proc(m: RegexMatch2, s: string): string
): int =
  var found = false
  var resultStr = ""
  var lastEnd = 0
  for m in content.findAll(pattern):
    if not found:
      let bounds = m.boundaries
      resultStr &= content[lastEnd ..< bounds.a]
      resultStr &= subFn(m, content)
      lastEnd = bounds.b + 1
      found = true
      break
  if found:
    resultStr &= content[lastEnd .. ^1]
    content = resultStr
    return 1
  return 0

proc apply*(input: string): string =
  result = input
  var patchesApplied = 0

  # Patch A: Force isEnabled in visualize server definition
  let alreadyA = "isEnabled:t=>(true)&&t.sessionType===\"cowork\"" in result
  if alreadyA:
    echo "  [OK] isEnabled: already patched (skipped)"
    patchesApplied += 1
  else:
    let patternA =
      re2"isEnabled:[\w$]+=>\([\w$]+\(""3444158716""\)\|\|!1\)&&[\w$]+\.sessionType===""cowork"""

    var countA = result.replaceFirst(
      patternA,
      proc(m: RegexMatch2, s: string): string =
        "isEnabled:t=>(true)&&t.sessionType===\"cowork\"",
    )
    if countA >= 1:
      echo &"  [OK] isEnabled: forced ON for cowork sessions ({countA} match)"
      patchesApplied += 1
    else:
      echo "  [FAIL] isEnabled pattern not found"

  # Patch B: Force hasImagine variable
  let flagCheck = re2"[\w$]+=[\w$]+\(""3444158716""\)\|\|!1"
  var alreadyB = true
  for m in result.findAll(flagCheck):
    alreadyB = false
    break
  if alreadyB and "\"3444158716\"" notin result:
    echo "  [OK] hasImagine: already patched (skipped)"
    patchesApplied += 1
  else:
    let patternB = re2"([\w$]+)=[\w$]+\(""3444158716""\)\|\|!1"
    var countB = result.replaceFirst(
      patternB,
      proc(m: RegexMatch2, s: string): string =
        let varName = s[m.group(0)]
        varName & "=!0",
    )
    if countB >= 1:
      echo &"  [OK] hasImagine: forced true ({countB} match)"
      patchesApplied += 1
    else:
      echo "  [FAIL] hasImagine pattern not found"

  if patchesApplied < EXPECTED_PATCHES:
    raise newException(
      ValueError,
      &"fix_imagine_linux: Only {patchesApplied}/{EXPECTED_PATCHES} patches applied",
    )

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_imagine_linux <file>"
    quit(1)
  let file = paramStr(1)
  echo "=== Patch: fix_imagine_linux ==="
  echo &"  Target: {file}"
  if not fileExists(file):
    echo &"  [FAIL] File not found: {file}"
    quit(1)
  let input = readFile(file)
  let output = apply(input)
  if output != input:
    writeFile(file, output)
    echo "  [PASS] Imagine/Visualize enabled for cowork sessions"
  else:
    echo "  [OK] Already patched, no changes needed"
