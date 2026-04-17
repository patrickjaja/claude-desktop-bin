# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
# Nim port of fix_imagine_linux.py.

import std/[os, strformat, strutils]
import regex

const ExpectedPatches = 2

proc apply*(input: string): string =
  var content = input
  var patchesApplied = 0

  # Patch A: Force isEnabled in visualize server definition
  let alreadyA = """isEnabled:t=>(true)&&t.sessionType==="cowork"""" in content
  if alreadyA:
    echo "  [OK] isEnabled: already patched (skipped)"
    inc patchesApplied
  else:
    let patternA = re2"""isEnabled:[\w$]+=>\([\w$]+\("3444158716"\)\|\|!1\)&&[\w$]+\.sessionType==="cowork""""
    let counter = new int
    counter[] = 0
    content = content.replace(patternA, proc (m: RegexMatch2, s: string): string =
      inc counter[]
      """isEnabled:t=>(true)&&t.sessionType==="cowork""""
    , limit = 1)
    if counter[] >= 1:
      echo &"  [OK] isEnabled: forced ON for cowork sessions ({counter[]} match)"
      inc patchesApplied
    else:
      echo "  [FAIL] isEnabled pattern not found"

  # Patch B: hasImagine variable
  let patternCheck = re2"""[\w$]+=[\w$]+\("3444158716"\)\|\|!1"""
  var hasCheck = false
  for _ in content.findAll(patternCheck):
    hasCheck = true
    break
  let alreadyB = (not hasCheck) and ("\"3444158716\"" notin content)
  if alreadyB:
    echo "  [OK] hasImagine: already patched (skipped)"
    inc patchesApplied
  else:
    let patternB = re2"""([\w$]+)=[\w$]+\("3444158716"\)\|\|!1"""
    let counter = new int
    counter[] = 0
    content = content.replace(patternB, proc (m: RegexMatch2, s: string): string =
      inc counter[]
      let v = s[m.group(0)]
      v & "=!0"
    , limit = 1)
    if counter[] >= 1:
      echo &"  [OK] hasImagine: forced true ({counter[]} match)"
      inc patchesApplied
    else:
      echo "  [FAIL] hasImagine pattern not found"

  if patchesApplied < ExpectedPatches:
    echo &"  [FAIL] Only {patchesApplied}/{ExpectedPatches} patches applied"
    raise newException(ValueError, "fix_imagine_linux: patches not fully applied")

  result = content

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_imagine_linux <path_to_index.js>"
    quit(1)
  let file = paramStr(1)
  echo "=== Patch: fix_imagine_linux ==="
  echo &"  Target: {file}"
  let input = readFile(file)
  let output = apply(input)
  if output != input:
    writeFile(file, output)
    echo "  [PASS] Imagine/Visualize enabled for cowork sessions"
  else:
    echo "  [OK] Already patched, no changes needed"
