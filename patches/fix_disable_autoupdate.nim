# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
#
# Disable auto-updater on Linux.
#
# The Windows Claude Desktop package includes Squirrel-based auto-update logic.
# On Linux, this can trigger false "Update downloaded" notifications because:
# - The isInstalled check (s$e) returns true for our repackaged app
# - Electron's autoUpdater may fire stale events from the Windows package
#
# This patch makes the isInstalled function return false on Linux, which:
# - Hides update-related menu items (visible: s$e())
# - Prevents the auto-update initialization from running
# - Stops false "Update heruntergeladen" (update downloaded) notifications
# - Leaves macOS and Windows behavior unchanged

import std/[os, strutils]
import regex

proc apply*(input: string): string =
  # Patch: Make the isInstalled function return false on Linux
  #
  # Original pattern (minified variable names change between versions):
  #   function XXX(){if(process.platform!=="win32")return YY.app.isPackaged;...
  # Newer versions may have an extra forceInstalled check before the platform check:
  #   function XXX(){if(ZZ.forceInstalled)return!0;if(process.platform!=="win32")return YY.app.isPackaged;...
  #
  # We insert a Linux early-return at the start of the function body:
  #   function XXX(){if(process.platform==="linux")return!1;...
  let pattern =
    re2"""(function [\w$]+\(\)\{)((?:if\([\w$]+\.forceInstalled\)return!0;)?if\(process\.platform!=="win32"\)return [\w$]+\.app\.isPackaged)"""
  var count = 0
  result = input.replace(
    pattern,
    proc(m: RegexMatch2, s: string): string =
      inc count
      let funcHead = s[m.group(0)]
      let body = s[m.group(1)]
      funcHead & """if(process.platform==="linux")return!1;""" & body,
  )
  if count == 0:
    echo "  [FAIL] isInstalled function: 0 matches"
    quit(1)
  echo "  [OK] isInstalled Linux gate: " & $count & " match(es)"

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_disable_autoupdate <path_to_index.js>"
    quit(1)
  let filePath = paramStr(1)
  echo "=== Patch: fix_disable_autoupdate ==="
  echo "  Target: " & filePath
  if not fileExists(filePath):
    echo "  [FAIL] File not found: " & filePath
    quit(1)
  let input = readFile(filePath)
  let output = apply(input)
  if output != input:
    writeFile(filePath, output)
    echo "  [PASS] Auto-updater disabled on Linux"
  else:
    echo "  [WARN] No changes made (pattern may have already been applied)"
