# @patch-target: app.asar.contents/.vite/renderer/main_window/assets/MainWindowPage-*.js
# @patch-type: nim
#
# Renderer-side companion to fix_native_frame.nim.
#
# Problem: with the integrated titlebar on Linux, the UI buttons (menu /
# sidebar toggle / search / back / forward) don't respond to hover or
# clicks. Cause: the React title-bar component renders a 36px-tall div
# with `-webkit-app-region: drag` (CSS class `nc-drag`) on macOS and Linux
# but `null` on Windows. On Linux integrated mode that drag region sits
# above the UI buttons and absorbs every pointer event before they get it.
# On macOS it's harmless because the height resolves to 0.
#
# Fix: make the main window branch return null on all platforms, matching
# upstream's Windows behavior. Effects:
#   * Windows:           unchanged (already returned null).
#   * macOS:             unchanged (was a 0px div, paints nothing either way).
#   * Linux integrated:  pointer events reach the UI buttons; Electron's
#                        titleBarOverlay still provides a draggable area.
#   * Linux GTK opt-out: also a no-op visually -- the GTK frame covered
#                        the div anyway, and the div was never interactive.
#
# Unconditional rather than gated on CLAUDE_NATIVE_TITLEBAR because the
# renderer can't read process.env: the preload (mainView.js) exposes a
# filtered process object with arch / platform / type / versions / argv
# only, no env. Since the change is a no-op everywhere else, gating is
# unnecessary.

import std/[os, strformat, strutils]
import regex

proc apply*(input: string): string =
  result = input
  if not result.contains("className:\"nc-drag\"") and result.contains("isMainWindow"):
    echo "  [INFO] already patched"
    return

  # Match the exact Pe() drag-region statement. Minified names (`z`, `e`,
  # `r`, `l`, the inner height var) are placeholders; we capture only the
  # isMainWindow argument so the rewritten `if(e)return null;` references
  # the same value.
  var n = 0
  result = result.replace(
    re2 r"""if\(!([\w$]+)&&([\w$]+)\)return [\w$]+===0\?null:[\w$]+\.jsx\("div",\{className:"nc-drag",style:\{height:`\$\{[\w$]+\}px`,width:"100%"\}\}\);""",
    proc(m: RegexMatch2, s: string): string =
      inc n
      "if(" & s[m.group(1)] & ")return null;",
  )
  if n != 1:
    raise newException(ValueError, &"Pe nc-drag pattern: {n}/1")
  echo &"  [OK] Pe nc-drag collapsed to if(e)return null;: {n}"

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_native_frame_renderer <file>"
    quit(1)
  let file = paramStr(1)
  echo "=== Patch: fix_native_frame_renderer ==="
  echo "  Target: " & file
  let orig = readFile(file)
  let patched = apply(orig)
  if patched != orig:
    writeFile(file, patched)
    echo "  [PASS] Pe drag region patched"
  else:
    echo "  [PASS] no changes needed"
