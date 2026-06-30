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
#
# v1.13576.0: upstream refactored the icon selection from a win32-only
# ternary (`isWin?e=...:e="TrayIconTemplate.png"`) into a `switch` on a
# build-time constant icon-type ("ico"/"template-image"/"png"):
#
#   let e;switch(G1r){
#     case"ico": e=ELEC.nativeTheme.shouldUseDarkColors?"Tray-Win32-Dark.ico":"Tray-Win32.ico";break;
#     case"template-image": e="TrayIconTemplate.png";break;
#     case"png": e=ELEC.nativeTheme.shouldUseDarkColors?"TrayIconTemplate-Dark.png":"TrayIconTemplate.png";break
#   }const t=...
#
# On Windows builds `G1r==="ico"`, so the switch picks `Tray-Win32.ico`,
# which doesn't exist in the Linux package. Rather than rewrite each case,
# we inject a Linux override right after the switch closes that forces the
# light icon (`TrayIconTemplate-Dark.png`) regardless of which case ran.

import std/[os, strutils]
import std/nre

proc apply*(input: string): string =
  # Idempotency: our injected override carries this exact literal.
  if input.contains(""";process.platform==="linux"&&(e="TrayIconLinux-Dark.png");"""):
    echo "  [OK] tray icon theme logic: already patched (skipped)"
    result = input
    return

  # Match the whole switch block that assigns the tray icon filename to `e`,
  # anchored on the three case literals so we pin the one correct site.
  # Variable names may contain $ (valid JS identifier), so use [\w$]+.
  let pattern =
    re"""let e;switch\([\w$]+\)\{case"ico":e=[\w$]+\.nativeTheme\.shouldUseDarkColors\?"Tray-Win32-Dark\.ico":"Tray-Win32\.ico";break;case"template-image":e="TrayIconTemplate\.png";break;case"png":e=[\w$]+\(\)==="gnome"\|\|[\w$]+\.nativeTheme\.shouldUseDarkColors\?"TrayIconLinux-Dark\.png":"TrayIconLinux\.png";break\}"""
  var count = 0
  result = input.replace(
    pattern,
    proc(m: RegexMatch): string =
      inc count
      # Re-emit the matched switch verbatim, then force the dark Linux icon on
      # Linux (trays there are universally dark; upstream now ships
      # TrayIconLinux.png / TrayIconLinux-Dark.png and the false branch of
      # Eni()==="gnome"||... would otherwise pick the light TrayIconLinux.png).
      # Trailing ';' is required: the matched switch is followed immediately
      # by `const t=...` with no line terminator, so without it the injected
      # expression statement runs into `const` (Unexpected token 'const').
      m.match & """;process.platform==="linux"&&(e="TrayIconLinux-Dark.png");""",
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
