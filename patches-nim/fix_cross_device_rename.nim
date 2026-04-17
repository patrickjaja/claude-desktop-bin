# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
# Nim port of fix_cross_device_rename.py

import std/[os, strformat, strutils]
import regex

proc apply*(input: string): string =
  var content = input
  let original = input

  let renamePattern = re2"(?<!try\{)await ([\w$]+)\.rename\(([\w$]+),([\w$]+)\)"
  var count = 0
  content = content.replace(renamePattern, proc (m: RegexMatch2, s: string): string =
    inc count
    let modVar = s[m.group(0)]
    let src = s[m.group(1)]
    let dst = s[m.group(2)]
    "await " & modVar & ".rename(" & src & "," & dst & ")" &
      ".catch(async e=>{if(e.code===\"EXDEV\"){" &
      "await " & modVar & ".copyFile(" & src & "," & dst & ");" &
      "await " & modVar & ".unlink(" & src & ")" &
      "}else throw e})"
  )

  if count >= 1:
    echo &"  [OK] Replaced {count} rename() calls with inline EXDEV fallback"
  else:
    # Idempotency check
    if content.contains(".catch(async e=>{if(e.code===\"EXDEV\""):
      echo "  [OK] Already patched (EXDEV catch marker present)"
      return original
    echo "  [FAIL] No unguarded rename() calls found and no EXDEV marker present"
    raise newException(ValueError, "fix_cross_device_rename: no rename calls found and no EXDEV marker")

  if content == original:
    echo "  [FAIL] re.subn reported matches but content unchanged"
    raise newException(ValueError, "fix_cross_device_rename: content unchanged despite matches")

  # Verify brace balance
  let origDelta = original.count('{') - original.count('}')
  let newDelta = content.count('{') - content.count('}')
  if origDelta != newDelta:
    let diff = newDelta - origDelta
    echo &"  [FAIL] Patch introduced brace imbalance: {diff:+d}"
    raise newException(ValueError, &"fix_cross_device_rename: brace imbalance {diff}")

  result = content

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_cross_device_rename <file>"
    quit(1)
  let file = paramStr(1)
  echo "=== Patch: fix_cross_device_rename ==="
  echo &"  Target: {file}"
  let input = readFile(file)
  let output = apply(input)
  if output != input:
    writeFile(file, output)
    echo "  [PASS] Cross-device rename fix applied"
  else:
    echo "  [OK] No changes needed"
