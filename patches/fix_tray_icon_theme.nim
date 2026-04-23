# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
#
# Patch Claude Desktop to use correct tray icon on Linux.
#
# On Windows, the app checks nativeTheme.shouldUseDarkColors to select the
# appropriate icon (light icon for dark theme, dark icon for light theme).
# On Linux, it always uses TrayIconTemplate.png (dark icon).
#
# Linux system trays are almost universally dark (GNOME, KDE, etc.), so we
# always need TrayIconTemplate-Dark.png (the light icon) regardless of the
# desktop theme setting.

import std/[os, strutils, options]
import std/nre

proc apply*(input: string): string =
  # Match the pattern with flexible variable names
  # Variable names may contain $ (valid JS identifier), so use [\w$]+
  # Uses \2 backreference for iconVar reuse in assignment
  let pattern =
    re"""([\w$]+)\?([\w$]+)=([\w$]+)\.nativeTheme\.shouldUseDarkColors\?"Tray-Win32-Dark\.ico":"Tray-Win32\.ico":\2="TrayIconTemplate\.png""""
  var count = 0
  result = input.replace(
    pattern,
    proc(m: RegexMatch): string =
      inc count
      let isWinVar = m.captures[0] # Ln
      let iconVar = m.captures[1] # e
      let electronVar = m.captures[2] # $e
      # On Windows: use .ico files with theme check
      # On Linux: always use light icon (Dark.png) since trays are universally dark
      isWinVar & "?" & iconVar & "=" & electronVar &
        """.nativeTheme.shouldUseDarkColors?"Tray-Win32-Dark.ico":"Tray-Win32.ico":""" &
        iconVar & """="TrayIconTemplate-Dark.png"""",
  )
  if count == 0:
    echo "  [FAIL] tray icon theme logic: 0 matches"
    quit(1)
  echo "  [OK] tray icon theme logic: " & $count & " match(es)"

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_tray_icon_theme <path_to_index.js>"
    quit(1)
  let filePath = paramStr(1)
  echo "=== Patch: fix_tray_icon_theme ==="
  echo "  Target: " & filePath
  if not fileExists(filePath):
    echo "  [FAIL] File not found: " & filePath
    quit(1)
  let input = readFile(filePath)
  let output = apply(input)
  if output != input:
    writeFile(filePath, output)
    echo "  [PASS] Tray icon theme patched successfully"
  else:
    echo "  [WARN] No changes made"
