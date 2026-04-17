# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
# Nim port of fix_tray_icon_theme.py

import std/[os, strformat]
import std/nre

proc apply*(input: string): string =
  var content = input

  let pattern = re"""([\w$]+)\?([\w$]+)=([\w$]+)\.nativeTheme\.shouldUseDarkColors\?"Tray-Win32-Dark\.ico":"Tray-Win32\.ico":\2="TrayIconTemplate\.png""""
  var count = 0
  content = content.replace(pattern, proc (m: RegexMatch): string =
    inc count
    let isWinVar = m.captures[0]
    let iconVar = m.captures[1]
    let electronVar = m.captures[2]
    isWinVar & "?" & iconVar & "=" & electronVar & ".nativeTheme.shouldUseDarkColors?\"Tray-Win32-Dark.ico\":\"Tray-Win32.ico\":" & iconVar & "=\"TrayIconTemplate-Dark.png\""
  )

  if count > 0:
    echo &"  [OK] tray icon theme logic: {count} match(es)"
  else:
    raise newException(ValueError, "fix_tray_icon_theme: tray icon theme logic: 0 matches")

  return content

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_tray_icon_theme <file>"
    quit(1)
  let file = paramStr(1)
  echo "=== Patch: fix_tray_icon_theme ==="
  echo &"  Target: {file}"
  let input = readFile(file)
  let output = apply(input)
  if output != input:
    writeFile(file, output)
  echo "  [PASS]"
