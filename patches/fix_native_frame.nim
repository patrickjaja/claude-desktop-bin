# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
# Patch Claude Desktop to use native window frames on Linux.
# Steps: preserve Quick Entry frame, replace frame:!1, titleBarStyle, autoHideMenuBar, icon.

import std/[os, strformat, strutils]
import regex

proc apply*(input: string): string =
  result = input

  # Step 1: Check if transparent window pattern exists (Quick Entry)
  let quickEntryPattern = "transparent:!0,frame:!1"
  let hasQuickEntry = quickEntryPattern in result
  if hasQuickEntry:
    echo "  [OK] Quick Entry pattern found (will preserve)"
  else:
    echo "  [INFO] Quick Entry pattern not found (may be already patched)"

  # Step 2: Temporarily mark the Quick Entry pattern
  let marker = "__QUICK_ENTRY_FRAME_PRESERVE__"
  if hasQuickEntry:
    result = result.replace(quickEntryPattern, "transparent:!0," & marker)

  # Step 3: Replace frame:!1 (false) with frame:true for main window
  let framePat = re2"frame\s*:\s*!1"
  var countFrame = 0
  result = result.replace(framePat, proc(m: RegexMatch2, s: string): string =
    inc countFrame
    "frame:true"
  )
  if countFrame > 0:
    echo &"  [OK] frame:!1 -> frame:true: {countFrame} match(es)"
  else:
    echo "  [INFO] No frame:!1 found outside Quick Entry (main window uses native frames by default)"

  # Step 4: Restore Quick Entry frame setting
  if hasQuickEntry:
    result = result.replace("transparent:!0," & marker, quickEntryPattern)
    echo "  [OK] Restored Quick Entry frame:!1 (transparent)"

  # Step 5: Replace titleBarStyle:"hidden" with platform-conditional for main window
  let mainTitlebarPat = re2"titleBarStyle:""hidden"",(titleBarOverlay:\w+)"
  var countTitlebar = 0
  result = result.replace(mainTitlebarPat, proc(m: RegexMatch2, s: string): string =
    inc countTitlebar
    let overlay = s[m.group(0)]
    "titleBarStyle:process.platform===\"linux\"?\"default\":\"hidden\"," & overlay
  )
  if countTitlebar > 0:
    echo &"  [OK] titleBarStyle:\"hidden\" -> platform-conditional: {countTitlebar} match(es)"
  else:
    if "titleBarStyle:process.platform===\"linux\"?\"default\":\"hidden\"" in result:
      echo "  [INFO] titleBarStyle already patched"
    else:
      echo "  [FAIL] titleBarStyle:\"hidden\" pattern not found near titleBarOverlay"
      raise newException(ValueError, "fix_native_frame: titleBarStyle pattern not found")

  # Step 6: Add autoHideMenuBar:true for Linux
  let autohidePat = re2"(titleBarStyle:process\.platform===""linux""\?""default"":""hidden""),(titleBarOverlay:\w+)"
  var countAutohide = 0
  result = result.replace(autohidePat, proc(m: RegexMatch2, s: string): string =
    inc countAutohide
    let titlebar = s[m.group(0)]
    let overlay = s[m.group(1)]
    titlebar & ",autoHideMenuBar:process.platform===\"linux\"," & overlay
  )
  if countAutohide > 0:
    echo &"  [OK] autoHideMenuBar added: {countAutohide} match(es)"
  else:
    if "autoHideMenuBar:process.platform===\"linux\"" in result:
      echo "  [INFO] autoHideMenuBar already patched"
    else:
      echo "  [FAIL] autoHideMenuBar pattern not found"
      raise newException(ValueError, "fix_native_frame: autoHideMenuBar pattern not found")

  # Step 7: Add window icon for Linux
  let iconPat = re2"(autoHideMenuBar:process\.platform===""linux""),(titleBarOverlay:\w+)"
  var countIcon = 0
  result = result.replace(iconPat, proc(m: RegexMatch2, s: string): string =
    inc countIcon
    let autohide = s[m.group(0)]
    let overlay = s[m.group(1)]
    autohide & ",icon:process.platform===\"linux\"?\"/usr/share/icons/hicolor/256x256/apps/claude-desktop.png\":void 0," & overlay
  )
  if countIcon > 0:
    echo &"  [OK] window icon added: {countIcon} match(es)"
  else:
    if "icon:process.platform===\"linux\"" in result:
      echo "  [INFO] window icon already patched"
    else:
      echo "  [FAIL] window icon pattern not found"
      raise newException(ValueError, "fix_native_frame: window icon pattern not found")

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_native_frame <file>"
    quit(1)
  let file = paramStr(1)
  echo "=== Patch: fix_native_frame ==="
  echo &"  Target: {file}"
  if not fileExists(file):
    echo &"  [FAIL] File not found: {file}"
    quit(1)
  let input = readFile(file)
  let output = apply(input)
  if output != input:
    writeFile(file, output)
    echo "  [PASS] Native frame patched successfully"
  else:
    echo "  [PASS] No changes needed (main window already uses native frames)"
