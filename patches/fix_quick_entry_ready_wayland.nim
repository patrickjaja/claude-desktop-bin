# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
#
# Fix Quick Entry ready-to-show hang on Wayland.
#
# Electron's 'ready-to-show' event never fires for transparent, frameless
# BrowserWindows on native Wayland. The Quick Entry window (Mlr function)
# awaits this event indefinitely, causing the overlay to never appear.
#
# This patch adds a 100ms timeout to the ready-to-show wait so the Quick
# Entry window proceeds to show even if the event never fires.
# The timeout is 100ms (reduced from 200ms): Chromium first-paint on Wayland
# typically completes in 30-50ms, so 100ms still provides comfortable headroom
# while saving 100ms on every Quick Entry open.

import std/[os, options]
import std/nre

proc apply*(input: string): string =
  # The Quick Entry show function waits for ready-to-show:
  #   <VAR>||await(<VAR2>==null?void 0:<VAR2>.catch(<P>=>{<LOG>.error("Quick Entry: Error waiting for ready %o",{error:<P>})}))
  # Variable names change every release (NEe/YEe, nK/AK, etc.) and so does the
  # logger module (`S` in v1.13576). We must REUSE the upstream logger and catch
  # param in the replacement -- hardcoding them (e.g. `R.error`) plants a latent
  # ReferenceError in the rejection branch even though the patch applies cleanly
  # and node --check passes. Capture both and emit them verbatim.
  # We wrap this in Promise.race with a 100ms timeout.
  let pat =
    re"""([\w$]+)\|\|await\(([\w$]+)==null\?void 0:\2\.catch\(([\w$]+)=>\{([\w$]+)\.error\("Quick Entry: Error waiting for ready %o",\{error:\3\}\)\}\)\)"""

  let m = input.find(pat)
  if m.isSome:
    let match = m.get
    let flagVar = match.captures[0]
    let promiseVar = match.captures[1]
    let catchParam = match.captures[2]
    let logVar = match.captures[3]
    let newStr =
      flagVar & "||await Promise.race([" & promiseVar & "==null?void 0:" & promiseVar &
      ".catch(" & catchParam & "=>{" & logVar &
      ".error(\"Quick Entry: Error waiting for ready %o\",{error:" & catchParam &
      "})}),new Promise(_r=>setTimeout(_r,100))])"
    result =
      input[0 ..< match.matchBounds.a] & newStr & input[match.matchBounds.b + 1 .. ^1]
    echo "  [OK] ready-to-show timeout (100ms) added (vars: " & flagVar & ", " &
      promiseVar & ", logger: " & logVar & ")"
  else:
    echo "  [FAIL] ready-to-show wait pattern not found"
    quit(1)

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_quick_entry_ready_wayland <path_to_index.js>"
    quit(1)
  let filePath = paramStr(1)
  echo "=== Patch: fix_quick_entry_ready_wayland ==="
  echo "  Target: " & filePath
  if not fileExists(filePath):
    echo "  [FAIL] File not found: " & filePath
    quit(1)
  let input = readFile(filePath)
  let output = apply(input)
  if output != input:
    writeFile(filePath, output)
    echo "  [PASS] Quick Entry ready-to-show timeout applied"
  else:
    echo "  [WARN] No changes made"
