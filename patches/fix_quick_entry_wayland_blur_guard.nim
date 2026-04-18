# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
# Guard Quick Entry blur-to-dismiss handler against spurious blurs on Wayland.
# Replaces Po.on("blur", ...) with focus-tracked variant.

import std/[os, strformat, strutils]
import regex

const FOCUS_GLOBAL = "__ceQEFocused"
const EXPECTED = 1

proc apply*(input: string): string =
  result = input

  # Idempotency check
  if FOCUS_GLOBAL in result:
    echo &"  [INFO] {FOCUS_GLOBAL} already present -- skipped"
    return result

  let pat = re2"([\w$]+)\.on\(""blur"",\(\)=>\{([\w$]+)\(null\)\}\)"

  var count = 0
  var resultStr = ""
  var lastEnd = 0
  for m in result.findAll(pat):
    if count == 0:
      let bounds = m.boundaries
      resultStr &= result[lastEnd ..< bounds.a]

      let win = result[m.group(0)]
      let fn = result[m.group(1)]
      let fg = FOCUS_GLOBAL

      resultStr &=
        win & ".on(\"focus\",()=>{globalThis." & fg & "=!0})," &
        win & ".on(\"blur\",()=>{" &
        "if(!globalThis." & fg & ")return;" &
        "globalThis." & fg & "=!1;" & fn & "(null)" &
        "})," &
        win & ".on(\"show\",()=>{globalThis." & fg & "=!1})," &
        win & ".on(\"hide\",()=>{globalThis." & fg & "=!1})"

      lastEnd = bounds.b + 1
      inc count
      break

  if count == 1:
    resultStr &= result[lastEnd .. ^1]
    result = resultStr
    echo "  [OK] blur handler replaced with focus-tracked variant"
  elif count > 1:
    raise newException(ValueError, &"fix_quick_entry_wayland_blur_guard: pattern matched {count} times (expected 1)")
  else:
    raise newException(ValueError, "fix_quick_entry_wayland_blur_guard: pattern did not match Po.on(\"blur\", () => EHA(null))")

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_quick_entry_wayland_blur_guard <file>"
    quit(1)
  let file = paramStr(1)
  echo "=== Patch: fix_quick_entry_wayland_blur_guard ==="
  echo &"  Target: {file}"
  if not fileExists(file):
    echo &"  [FAIL] File not found: {file}"
    quit(1)
  let input = readFile(file)
  let output = apply(input)
  if output != input:
    writeFile(file, output)
    echo &"  [PASS] {EXPECTED}/{EXPECTED} applied"
  else:
    echo &"  [PASS] No changes needed -- already patched ({EXPECTED}/{EXPECTED})"
