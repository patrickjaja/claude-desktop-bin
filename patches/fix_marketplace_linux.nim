# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
#
# Force CCD mode for marketplace operations on Linux.
#
# The CCD/Cowork gate function determines whether plugin operations use
# host-local CCD paths or account-scoped Cowork paths. On Linux there's
# no VM, so all operations should use the CCD (host-local) path.

import std/[os, options]
import std/nre

proc apply*(input: string): string =
  let idempotencyPattern = re"""function [\w$]+\([\w$]+\)\{return process\.platform==="linux"\|\|"""
  if input.contains(idempotencyPattern):
    echo "  [OK] Already patched (Linux platform check found in CCD gate)"
    echo "  [PASS] No changes needed"
    return input

  # CCD/Cowork gate -- force CCD mode on Linux
  # Uses backreference \2 to ensure the param name repeats consistently
  let pattern = re"""function ([\w$]+)\(([\w$]+)\)\{return\((\2)==null\?void 0:\3\.mode\)==="ccd"\}"""
  let m = input.find(pattern)
  if m.isSome:
    let match = m.get
    let fnName = match.captures[0]
    let param = match.captures[1]
    let replacement = "function " & fnName & "(" & param & """){return process.platform==="linux"||(""" & param & "==null?void 0:" & param & """.mode)==="ccd"}"""
    result = input[0 ..< match.matchBounds.a] & replacement & input[match.matchBounds.b + 1 .. ^1]
    echo "  [OK] CCD/Cowork gate: force CCD mode on Linux (1 match)"
  else:
    echo "  [FAIL] CCD/Cowork gate: 0 matches"
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
  if output == input:
    echo "  [WARN] No changes made (pattern may have already been applied)"
  else:
    writeFile(filePath, output)
    echo "  [PASS] Marketplace Linux patch applied"
