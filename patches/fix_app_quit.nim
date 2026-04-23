# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
#
# Fix app not quitting after cleanup completes.
#
# After the will-quit handler calls preventDefault() and runs cleanup,
# calling app.quit() again becomes a no-op on Linux. The will-quit event
# never fires again, leaving the app stuck.
#
# Solution: Use app.exit(0) instead of app.quit() after cleanup is complete.
# Since all cleanup handlers have already run (mcp-shutdown, quick-entry-cleanup,
# prototype-cleanup), we can safely force exit. Using setImmediate ensures
# the exit happens in the next event loop tick.

import std/[os, strutils]
import regex

proc apply*(input: string): string =
  # Original pattern: clearTimeout(n)}XX&&YY.app.quit()}
  # Variables change between versions (e.g., S_&&he -> TS&&ce)
  # Note: [\w$]+ is used because minified JS names can contain $ (e.g., f$, u$)
  # The XX&&YY.app.quit() doesn't work after preventDefault() on Linux
  # Replace with setImmediate + app.exit(0) for reliable exit
  let pattern = re2"(clearTimeout\([\w$]+\)\})([\w$]+)&&([\w$]+)(\.app\.quit\(\))"
  var count = 0
  result = input.replace(
    pattern,
    proc(m: RegexMatch2, s: string): string =
      inc count
      let grp0 = s[m.group(0)] # clearTimeout(n)}
      let flagVar = s[m.group(1)] # XX
      let electronVar = s[m.group(2)] # YY
      # group(3) is .app.quit() -- we discard it
      grp0 & "if(" & flagVar & "){setImmediate(()=>" & electronVar & ".app.exit(0))}",
  )
  if count == 0:
    if ".app.quit()" in input:
      echo "  [INFO] Found '.app.quit()' in file but pattern didn't match"
    echo "  [FAIL] app.quit pattern: 0 matches (may need pattern update)"
    quit(1)
  echo "  [OK] app.quit -> app.exit: " & $count & " match(es)"

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_app_quit <file>"
    quit(1)
  let filePath = paramStr(1)
  echo "=== Patch: fix_app_quit ==="
  echo "  Target: " & filePath
  let input = readFile(filePath)
  let output = apply(input)
  writeFile(filePath, output)
  echo "  [PASS] App quit patched successfully"
