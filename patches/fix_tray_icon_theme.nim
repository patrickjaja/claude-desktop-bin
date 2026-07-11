# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
#
# Patch Claude Desktop to use correct tray icon on Linux.
#
# The official Linux .deb has native Linux tray-icon logic: a `switch` on a
# build-time icon-type constant ("ico"/"template-image"/"png"; "png" on Linux
# builds), whose png case picks the icon per desktop environment and theme:
#
#   let e;switch(G1r){
#     case"ico": e=ELEC.nativeTheme.shouldUseDarkColors?"Tray-Win32-Dark.ico":"Tray-Win32.ico";break;
#     case"template-image": e="TrayIconTemplate.png";break;
#     case"png": e=ere()==="gnome"||ELEC.nativeTheme.shouldUseDarkColors?"TrayIconLinux-Dark.png":"TrayIconLinux.png";break
#   }const t=...
#
# That heuristic is wrong for us: it only forces the dark icon on GNOME, and
# otherwise follows nativeTheme. But Linux system trays are almost universally
# dark (KDE, Xfce, status-notifier hosts, ...) regardless of the app/desktop
# theme, so on a light theme outside GNOME upstream picks the dark-on-dark
# TrayIconLinux.png and the icon is invisible. We deliberately OVERRIDE the
# native heuristic: inject a statement right after the switch that forces
# TrayIconLinux-Dark.png (the light glyph) on Linux regardless of which case
# ran. (Minified names like G1r/ere change every release - the regex uses
# [\w$]+ wildcards; the icon files ship in the official .deb.)

import std/os
import std/nre

proc apply*(input: string): string =
  # Idempotency: our injected override carries this shape (the icon variable
  # is minified and renames between releases - e in <=1.18286, t in 1.19367).
  if input.contains(
    re""";process\.platform==="linux"&&\([\w$]+="TrayIconLinux-Dark\.png"\);"""
  ):
    echo "  [OK] tray icon theme logic: already patched (skipped)"
    result = input
    return

  # Match the whole switch block that assigns the tray icon filename to the
  # (minified, capture it) icon variable, anchored on the three case literals
  # so we pin the one correct site.
  # Variable names may contain $ (valid JS identifier), so use [\w$]+.
  let pattern =
    re"""let ([\w$]+);switch\([\w$]+\)\{case"ico":\1=[\w$]+\.nativeTheme\.shouldUseDarkColors\?"Tray-Win32-Dark\.ico":"Tray-Win32\.ico";break;case"template-image":\1="TrayIconTemplate\.png";break;case"png":\1=[\w$]+\(\)==="gnome"\|\|[\w$]+\.nativeTheme\.shouldUseDarkColors\?"TrayIconLinux-Dark\.png":"TrayIconLinux\.png";break\}"""
  var count = 0
  result = input.replace(
    pattern,
    proc(m: RegexMatch): string =
      inc count
      let iconVar = m.captures[0]
      # Re-emit the matched switch verbatim, then force the dark Linux icon on
      # Linux (trays there are universally dark; upstream now ships
      # TrayIconLinux.png / TrayIconLinux-Dark.png and the false branch of
      # Eni()==="gnome"||... would otherwise pick the light TrayIconLinux.png).
      # Trailing ';' is required: the matched switch is followed immediately
      # by `const t=...` with no line terminator, so without it the injected
      # expression statement runs into `const` (Unexpected token 'const').
      m.match & ";process.platform===\"linux\"&&(" & iconVar &
        "=\"TrayIconLinux-Dark.png\");",
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
