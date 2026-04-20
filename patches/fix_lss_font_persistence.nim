# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
#
# Fix LSS-* preference persistence (chatFont, backgroundAnimation, etc.)
#
# The claude.ai web app stores user preferences in localStorage with a
# per-session tabId UUID. On macOS the window-all-closed handler is a
# no-op (process stays alive, tabId survives across window open/close).
# On Linux, app.quit() is called, killing the process — next launch
# gets a fresh tabId and can't read the old preferences.
#
# Fix: make window-all-closed a no-op on Linux too, matching macOS.
# The tray icon already handles reopen (click) and quit (right-click).
# The main window close handler already does preventDefault()+hide().
#
# Break risk: LOW — simple regex on a stable Electron event pattern.

import std/[os, strutils]
import regex

proc apply*(input: string): string =
  # Check if already patched: empty handler body
  let alreadyPatched = re2"""\.on\("window-all-closed",\(\)=>\{\}\)"""
  if input.contains(alreadyPatched):
    echo "  [OK] window-all-closed: already patched (skipped)"
    return input

  # Pattern: .on("window-all-closed",()=>{XX||YY()})
  # XX = darwin flag (en), YY = quit function (bf)
  # Replace the body with a no-op so the process stays alive
  let pattern = re2"""(\.on\("window-all-closed",\(\)=>\{)([\w$]+\|\|[\w$]+\(\))(\}\))"""
  var count = 0
  result = input.replace(pattern, proc(m: RegexMatch2, s: string): string =
    inc count
    let prefix = s[m.group(0)]  # .on("window-all-closed",()=>{
    let suffix = s[m.group(2)]  # })
    prefix & suffix
  )
  if count == 0:
    if "window-all-closed" in input:
      echo "  [INFO] Found 'window-all-closed' but pattern didn't match"
    echo "  [FAIL] window-all-closed pattern: 0 matches"
    quit(1)
  if count > 1:
    echo "  [FAIL] window-all-closed pattern: " & $count & " matches (expected 1)"
    quit(1)
  echo "  [OK] window-all-closed: removed quit gate (1 match)"

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_lss_font_persistence <file>"
    quit(1)
  let filePath = paramStr(1)
  echo "=== Patch: fix_lss_font_persistence ==="
  echo "  Target: " & filePath
  if not fileExists(filePath):
    echo "  [FAIL] File not found: " & filePath
    quit(1)
  let input = readFile(filePath)
  let output = apply(input)
  if output != input:
    writeFile(filePath, output)
    echo "  [PASS] LSS font persistence fix applied"
  else:
    echo "  [WARN] No changes made"
