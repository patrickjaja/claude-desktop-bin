# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
# Nim port of fix_asar_folder_drop.py
# Uses std/nre because the argv pattern uses a \2 backreference.

import std/[os, strformat, options]
import std/nre

proc apply*(input: string): string =
  var content = input
  let original = input

  # Idempotency check: look for the .asar filter already injected
  let already = re"""function [\w$]+\([\w$]+\)\{[\w$]+=[\w$]+\.filter\([\w$]+=>!/\\\.asar/"""
  if content.find(already).isSome:
    echo "  [SKIP] Already patched (.asar filter found)"
    return content

  # 1. Patch noe() file-drop convergence point
  let patNoe = re"""(function [\w$]+\()([\w$]+)(\)\{)(if\([\w$]+\.info\(`Handling file drop:)"""
  var m = content.find(patNoe)
  if m.isSome:
    let mm = m.get
    let g1 = mm.captures[0]
    let arg = mm.captures[1]
    let g3 = mm.captures[2]
    let g4 = mm.captures[3]
    let replacement =
      g1 & arg & g3 &
      arg & "=" & arg & ".filter(f=>!/\\.asar/.test(f));if(!" & arg & ".length)return;" &
      g4
    let s = mm.matchBounds
    content = content[0 ..< s.a] & replacement & content[s.b + 1 .. ^1]
    echo "  [OK] noe() file-drop filter: 1 match(es)"
  else:
    echo "  [FAIL] noe() pattern: 0 matches"
    raise newException(ValueError, "fix_asar_folder_drop: noe pattern not found")

  # 2. Guard second-instance argv parser (KXn) — uses \2 backref
  let patArgv = re"""(for\(const )([\w$]+)( of [\w$]+\.slice\(1\)\))(if\()(![\w$]+\(\2\))"""
  var m2 = content.find(patArgv)
  if m2.isSome:
    let mm = m2.get
    let g1 = mm.captures[0]
    let v = mm.captures[1]
    let g3 = mm.captures[2]
    let g4 = mm.captures[3]
    let g5 = mm.captures[4]
    let replacement =
      g1 & v & g3 & g4 & "!/\\.asar/.test(" & v & ")&&" & g5
    let s = mm.matchBounds
    content = content[0 ..< s.a] & replacement & content[s.b + 1 .. ^1]
    echo "  [OK] Second-instance argv parser (KXn): 1 match(es)"
  else:
    echo "  [WARN] Second-instance argv parser: 0 matches (noe filter is primary)"

  result = content

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_asar_folder_drop <file>"
    quit(1)
  let file = paramStr(1)
  echo "=== Patch: fix_asar_folder_drop ==="
  echo &"  Target: {file}"
  let input = readFile(file)
  let output = apply(input)
  if output != input:
    writeFile(file, output)
    echo "  [PASS] Patch applied"
  else:
    echo "  [WARN] No changes made"
