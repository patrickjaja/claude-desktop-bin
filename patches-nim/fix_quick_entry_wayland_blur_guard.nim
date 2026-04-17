# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
# Nim port of fix_quick_entry_wayland_blur_guard.py

import std/[os, strformat, strutils]
import regex

const FOCUS_GLOBAL = "__ceQEFocused"

proc apply*(input: string): string =
  var content = input
  var applied = 0
  const EXPECTED = 1

  if strutils.contains(content, FOCUS_GLOBAL):
    echo &"  [INFO] {FOCUS_GLOBAL} already present — skipped"
    return content

  let pat = re2"""([\w$]+)\.on\("blur",\(\)=>\{([\w$]+)\(null\)\}\)"""
  var count = 0
  content = content.replace(pat, proc (m: RegexMatch2, s: string): string =
    inc count
    let win = s[m.group(0)]
    let fn = s[m.group(1)]
    let fg = FOCUS_GLOBAL
    win & ".on(\"focus\",()=>{globalThis." & fg & "=!0})," &
      win & ".on(\"blur\",()=>{" &
        "if(!globalThis." & fg & ")return;" &
        "globalThis." & fg & "=!1;" &
        fn & "(null)" &
      "})," &
      win & ".on(\"show\",()=>{globalThis." & fg & "=!1})," &
      win & ".on(\"hide\",()=>{globalThis." & fg & "=!1})"
  )

  if count == 1:
    echo "  [OK] blur handler replaced with focus-tracked variant"
    applied += 1
  elif count > 1:
    raise newException(ValueError, &"fix_quick_entry_wayland_blur_guard: pattern matched {count} times (expected 1)")
  else:
    raise newException(ValueError, "fix_quick_entry_wayland_blur_guard: pattern did not match Po.on(\"blur\", () => EHA(null))")

  if applied < EXPECTED:
    raise newException(ValueError, &"fix_quick_entry_wayland_blur_guard: Only {applied}/{EXPECTED} applied")

  return content

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_quick_entry_wayland_blur_guard <file>"
    quit(1)
  let file = paramStr(1)
  echo "=== Patch: fix_quick_entry_wayland_blur_guard ==="
  echo &"  Target: {file}"
  let input = readFile(file)
  let output = apply(input)
  if output != input:
    writeFile(file, output)
  echo "  [PASS]"
