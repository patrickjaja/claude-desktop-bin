# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
# Nim port of fix_native_frame.py.

import std/[os, strformat, strutils]
import regex

proc apply*(input: string): string =
  var content = input
  let originalContent = input

  # Step 1: Check Quick Entry pattern exists
  const quickEntryPattern = "transparent:!0,frame:!1"
  let hasQuickEntry = quickEntryPattern in content
  if hasQuickEntry:
    echo "  [OK] Quick Entry pattern found (will preserve)"
  else:
    echo "  [INFO] Quick Entry pattern not found (may be already patched)"

  # Step 2: Mark Quick Entry
  const marker = "__QUICK_ENTRY_FRAME_PRESERVE__"
  if hasQuickEntry:
    content = content.replace(quickEntryPattern, "transparent:!0," & marker)

  # Step 3: frame:!1 -> frame:true
  let framePattern = re2"""frame\s*:\s*!1"""
  let counter = new int
  counter[] = 0
  content = content.replace(framePattern, proc (m: RegexMatch2, s: string): string =
    inc counter[]
    "frame:true"
  )
  if counter[] > 0:
    echo &"  [OK] frame:!1 -> frame:true: {counter[]} match(es)"
  else:
    echo "  [INFO] No frame:!1 found outside Quick Entry (main window uses native frames by default)"

  # Step 4: Restore Quick Entry
  if hasQuickEntry:
    content = content.replace("transparent:!0," & marker, quickEntryPattern)
    echo "  [OK] Restored Quick Entry frame:!1 (transparent)"

  # Step 5: titleBarStyle pattern
  let mainTitlebar = re2"""titleBarStyle:"hidden",(titleBarOverlay:\w+)"""
  let tbCounter = new int
  tbCounter[] = 0
  content = content.replace(mainTitlebar, proc (m: RegexMatch2, s: string): string =
    inc tbCounter[]
    let overlay = s[m.group(0)]
    "titleBarStyle:process.platform===\"linux\"?\"default\":\"hidden\"," & overlay
  )
  if tbCounter[] > 0:
    echo &"  [OK] titleBarStyle:\"hidden\" -> platform-conditional: {tbCounter[]} match(es)"
  else:
    if """titleBarStyle:process.platform==="linux"?"default":"hidden"""" in content:
      echo "  [INFO] titleBarStyle already patched"
    else:
      echo "  [FAIL] titleBarStyle:\"hidden\" pattern not found near titleBarOverlay"
      raise newException(ValueError, "fix_native_frame: titleBarStyle pattern not found")

  # Step 6: autoHideMenuBar
  let autohidePattern = re2"""(titleBarStyle:process\.platform==="linux"\?"default":"hidden"),(titleBarOverlay:\w+)"""
  let ahCounter = new int
  ahCounter[] = 0
  content = content.replace(autohidePattern, proc (m: RegexMatch2, s: string): string =
    inc ahCounter[]
    let titlebar = s[m.group(0)]
    let overlay = s[m.group(1)]
    titlebar & ",autoHideMenuBar:process.platform===\"linux\"," & overlay
  )
  if ahCounter[] > 0:
    echo &"  [OK] autoHideMenuBar added: {ahCounter[]} match(es)"
  else:
    if """autoHideMenuBar:process.platform==="linux"""" in content:
      echo "  [INFO] autoHideMenuBar already patched"
    else:
      echo "  [FAIL] autoHideMenuBar pattern not found"
      raise newException(ValueError, "fix_native_frame: autoHideMenuBar pattern not found")

  # Step 7: window icon
  let iconPattern = re2"""(autoHideMenuBar:process\.platform==="linux"),(titleBarOverlay:\w+)"""
  let icCounter = new int
  icCounter[] = 0
  content = content.replace(iconPattern, proc (m: RegexMatch2, s: string): string =
    inc icCounter[]
    let autohide = s[m.group(0)]
    let overlay = s[m.group(1)]
    autohide & ",icon:process.platform===\"linux\"?\"/usr/share/icons/hicolor/256x256/apps/claude-desktop.png\":void 0," & overlay
  )
  if icCounter[] > 0:
    echo &"  [OK] window icon added: {icCounter[]} match(es)"
  else:
    if """icon:process.platform==="linux"""" in content:
      echo "  [INFO] window icon already patched"
    else:
      echo "  [FAIL] window icon pattern not found"
      raise newException(ValueError, "fix_native_frame: window icon pattern not found")

  result = content

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_native_frame <path_to_index.js>"
    quit(1)
  let file = paramStr(1)
  echo "=== Patch: fix_native_frame ==="
  echo &"  Target: {file}"
  let input = readFile(file)
  let output = apply(input)
  if output != input:
    writeFile(file, output)
    echo "  [PASS] Native frame patched successfully"
  else:
    echo "  [PASS] No changes needed (main window already uses native frames)"
