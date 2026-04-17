# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
# Nim port of fix_marketplace_linux.py.
# Uses std/nre (PCRE) because pattern has backreferences.

import std/[os, strformat, options]
import std/nre

proc apply*(input: string): string =
  var content = input

  # Idempotency
  let idempotent = re"""function [\w$]+\([\w$]+\)\{return process\.platform==="linux"\|\|"""
  if content.find(idempotent).isSome:
    echo "  [OK] Already patched (Linux platform check found in CCD gate)"
    echo "  [PASS] No changes needed"
    return content

  # Pattern with backrefs:
  # function ([\w$]+)\(([\w$]+)\)\{return\((\2)==null\?void 0:\3\.mode\)==="ccd"\}
  let pattern = re"""function ([\w$]+)\(([\w$]+)\)\{return\((\2)==null\?void 0:\3\.mode\)==="ccd"\}"""
  var count = 0
  content = content.replace(pattern, proc (m: RegexMatch): string =
    inc count
    let fn = m.captures[0]
    let param = m.captures[1]
    "function " & fn & "(" & param & "){return process.platform===\"linux\"||(" & param & "==null?void 0:" & param & ".mode)===\"ccd\"}"
  )
  if count >= 1:
    echo &"  [OK] CCD/Cowork gate: force CCD mode on Linux ({count} match)"
  else:
    echo "  [FAIL] CCD/Cowork gate: 0 matches"
    raise newException(ValueError, "fix_marketplace_linux: pattern not found")

  if content == input:
    echo "  [WARN] No changes made (pattern may have already been applied)"
    return content

  result = content

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_marketplace_linux <path_to_index.js>"
    quit(1)
  let file = paramStr(1)
  echo "=== Patch: fix_marketplace_linux ==="
  echo &"  Target: {file}"
  let input = readFile(file)
  let output = apply(input)
  if output != input:
    writeFile(file, output)
    echo "  [PASS] Marketplace Linux patch applied"
