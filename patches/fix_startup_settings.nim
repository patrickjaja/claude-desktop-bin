# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
#
# Patch Claude Desktop to fix startup settings on Linux.
#
# On Linux, Electron's app.getLoginItemSettings() returns undefined values for
# openAtLogin and executableWillLaunchAtLogin, causing validation errors.
# This patch adds a Linux platform check to return false immediately.
#
# Linux autostart is typically handled via .desktop files in ~/.config/autostart/
# which is outside the app's control anyway.

import std/[os, strutils]
import regex

proc apply*(input: string): string =
  var patchesApplied = 0
  const expectedPatches = 2

  # Pattern 1: isStartupOnLoginEnabled function
  # Add Linux platform check before the existing env var check
  let pattern1 = re2"""isStartupOnLoginEnabled\(\)\{if\(process\.env\.CLAUDE_AVOID_READING_LOGING_ITEM_SETTINGS\)return!1;"""
  let replacement1 = """isStartupOnLoginEnabled(){if(process.platform==="linux"||process.env.CLAUDE_AVOID_READING_LOGING_ITEM_SETTINGS)return!1;"""

  var count1 = 0
  result = input.replace(pattern1, proc(m: RegexMatch2, s: string): string =
    inc count1
    replacement1
  )
  if count1 > 0:
    patchesApplied += count1
    echo "  [OK] isStartupOnLoginEnabled: " & $count1 & " match(es)"
  else:
    echo "  [FAIL] isStartupOnLoginEnabled: 0 matches"

  # Pattern 2: setStartupOnLoginEnabled function - make it a no-op on Linux
  let pattern2 = re2"""setStartupOnLoginEnabled\(([\w$]+)\)\{([\w$]+)\.debug\("""
  var count2 = 0
  let intermediate = result
  result = intermediate.replace(pattern2, proc(m: RegexMatch2, s: string): string =
    inc count2
    let argVar = s[m.group(0)]
    let loggerVar = s[m.group(1)]
    "setStartupOnLoginEnabled(" & argVar & """){if(process.platform==="linux")return;""" & loggerVar & ".debug("
  )
  if count2 > 0:
    patchesApplied += count2
    echo "  [OK] setStartupOnLoginEnabled: " & $count2 & " match(es)"
  else:
    echo "  [INFO] setStartupOnLoginEnabled: 0 matches (optional)"

  if patchesApplied < expectedPatches:
    echo "  [FAIL] Only " & $patchesApplied & "/" & $expectedPatches & " patches applied -- check [WARN]/[FAIL] messages above"
    quit(1)

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_startup_settings <path_to_index.js>"
    quit(1)
  let filePath = paramStr(1)
  echo "=== Patch: fix_startup_settings ==="
  echo "  Target: " & filePath
  if not fileExists(filePath):
    echo "  [FAIL] File not found: " & filePath
    quit(1)
  let input = readFile(filePath)
  let output = apply(input)
  if output != input:
    writeFile(filePath, output)
    echo "  [PASS] Startup settings patched successfully"
  else:
    echo "  [WARN] No changes made (patterns matched but already applied)"
