# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
# Prevent app.asar from being dispatched to Cowork on Linux.
# Two fixes: noe() file-drop filter and second-instance argv parser guard.
# Uses std/nre for backreference support in patterns.

import std/[os, strformat, options]
import std/nre

const EXPECTED_PATCHES = 2

proc apply*(input: string): string =
  result = input
  var patchesApplied = 0

  # Idempotency check
  let idempotencyPat =
    re"function [\w$]+\([\w$]+\)\{(?:var [\w$]+(?:,[\w$]+)*;)?[\w$]+=[\w$]+\.filter\([\w$]+=>!/\\\.asar/"
  if result.find(idempotencyPat).isSome:
    echo "  [SKIP] Already patched (.asar filter found)"
    return result

  # Patch A: noe() file-drop convergence filter
  # v1.19367.0: minifier emits an optional `var r;` (hoisted temp) between the
  # opening brace and the `if(...)`; the filter injection goes after it.
  let patNoe =
    re"(function [\w$]+\()([\w$]+)(\)\{(?:var [\w$]+(?:,[\w$]+)*;)?)(if\([\w$]+\.info\(`Handling file drop:)"

  let mA = result.find(patNoe)
  if mA.isSome:
    let m = mA.get
    let arg = m.captures[1]
    let replacement =
      m.captures[0] & arg & m.captures[2] & arg & "=" & arg &
      ".filter(f=>!/\\.asar/.test(f));if(!" & arg & ".length)return;" & m.captures[3]
    result =
      result[0 ..< m.matchBounds.a] & replacement & result[m.matchBounds.b + 1 .. ^1]
    echo "  [OK] noe() file-drop filter: 1 match(es)"
    patchesApplied += 1
  else:
    echo "  [FAIL] noe() pattern: 0 matches"
    raise newException(ValueError, "fix_asar_folder_drop: noe() pattern not found")

  # Patch B: Second-instance argv parser guard (uses \2 backreference)
  #
  # v1.9659.4: for(const X of Y.slice(1))if(!Z(X)){...
  # v1.11187.4: the .slice(1).filter(...) was hoisted into a local var, so the
  #   loop is now `for(const X of <var>)if(!Z(X)){if(NiA(X)){hp(X,...,"skill file")`.
  # v1.20186.1: the loop body gained braces and a leading directory-collector
  #   block: `for(const X of Y){if(lM(X)){r??(r=X);continue}if(!Z(X)){if(lF(X)){
  #   ru(X,...,"skill file")`. Fold that new prefix into the pre-guard capture.
  # Anchor on the trailing `"skill file"` arg to keep the match unique (there is
  # exactly one such loop in the bundle).
  let patArgv =
    re"(for\(const )([\w$]+)( of [\w$]+\)\{if\([\w$]+\(\2\)\)\{[\w$]+\?\?\([\w$]+=\2\);continue\})(if\()(![\w$]+\(\2\))(\)\{if\([\w$]+\(\2\)\)\{[\w$]+\(\2,[\w$]+,""skill file""\))"

  let mB = result.find(patArgv)
  if mB.isSome:
    let m = mB.get
    let varName = m.captures[1]
    let replacement =
      m.captures[0] & varName & m.captures[2] & m.captures[3] & "!/\\.asar/.test(" &
      varName & ")&&" & m.captures[4] & m.captures[5]
    result =
      result[0 ..< m.matchBounds.a] & replacement & result[m.matchBounds.b + 1 .. ^1]
    echo "  [OK] Second-instance argv parser: 1 match(es)"
    patchesApplied += 1
  else:
    echo "  [FAIL] Second-instance argv parser: 0 matches"

  if patchesApplied < EXPECTED_PATCHES:
    raise newException(
      ValueError,
      &"fix_asar_folder_drop: Only {patchesApplied}/{EXPECTED_PATCHES} patches applied",
    )

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_asar_folder_drop <file>"
    quit(1)
  let file = paramStr(1)
  echo "=== Patch: fix_asar_folder_drop ==="
  echo &"  Target: {file}"
  if not fileExists(file):
    echo &"  [FAIL] File not found: {file}"
    quit(1)
  let input = readFile(file)
  let output = apply(input)
  if output != input:
    writeFile(file, output)
    echo &"  [PASS] Patch applied ({EXPECTED_PATCHES}/{EXPECTED_PATCHES} patches applied)"
  else:
    echo &"  [FAIL] No changes made"
    quit(1)
