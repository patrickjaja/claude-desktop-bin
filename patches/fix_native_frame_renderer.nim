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
# upstream's Windows behavior.
#
# STATUS (v1.13576): UPSTREAMED. The Pe() title-bar component now returns
# null for the main window natively as its first statement:
#   function Pe({isMainWindow:e,...}){if(e)return null;...}
# The old macOS/Linux drag-region branch (a `nc-drag` div with width:100%)
# that this patch used to collapse no longer exists, so no rewrite is needed.
#
# This patch is therefore now a REGRESSION GUARD rather than an active fix:
# it asserts that upstream still short-circuits the main window to null. If a
# future release reintroduces a drag region (the original bug), the positive
# assertion below fails the build loudly instead of silently shipping broken
# pointer handling on Linux. Do NOT downgrade this to a silent skip -- the
# whole point is to notice an upstream regression.

import std/[os, strformat]
import regex

proc apply*(input: string): string =
  result = input

  # Upstreamed form: the main-window branch returns null as the component's
  # first statement, e.g. function Pe({isMainWindow:e,...}){if(e)return null;...}
  # The `{isMainWindow:` destructure occurs exactly once in the renderer bundle,
  # so this anchor is unambiguous without a backreference (the `regex`/re2
  # engine treats \1 as an octal escape, unlike nre, so we avoid it here).
  let guard = re2 r"""\{isMainWindow:[\w$]+,[^}]{0,100}\}\)\{if\([\w$]+\)return null"""

  var found = 0
  for m in result.findAll(guard):
    inc found
  if found >= 1:
    echo &"  [OK] upstream main-window null short-circuit present (regression guard satisfied): {found}"
    return

  # If the upstreamed null-return is gone, upstream may have reintroduced the
  # drag region this patch originally fixed. Fail loudly -- this needs a human
  # to re-evaluate whether the active rewrite must be restored.
  raise newException(
    ValueError,
    "fix_native_frame_renderer: upstream main-window null short-circuit " &
      "({isMainWindow:e,...}){if(e)return null) NOT found. Upstream may have " &
      "regressed the native-frame fix -- re-audit the Pe() title-bar component.",
  )

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
