# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
# Patch tray menu handler to prevent DBus race conditions on Linux.
# Makes tray function async, adds mutex guard, adds delay after destroy.

import std/[os, strformat, strutils]
import regex

proc apply*(input: string): string =
  result = input
  var failed = false

  # Step 1: Find the tray function name from menuBarEnabled listener
  let listenerPat = re2"on\(""menuBarEnabled"",\(\)=>\{(\w+)\(\)\}\)"
  var trayFunc = ""
  for m in result.findAll(listenerPat):
    trayFunc = result[m.group(0)]
    break

  if trayFunc == "":
    echo "  [FAIL] menuBarEnabled listener: 0 matches, expected >= 1"
    failed = true
  else:
    echo &"  [OK] menuBarEnabled listener: found tray function '{trayFunc}'"

  # Step 2: Find tray variable name
  var trayVar = ""
  if trayFunc != "":
    let varPat = re2("let ([\\w$]+)=null;(?:async )?function " & trayFunc)
    for m in result.findAll(varPat):
      trayVar = result[m.group(0)]
      break

    if trayVar == "":
      echo "  [FAIL] tray variable: 0 matches, expected >= 1"
      failed = true
    else:
      echo &"  [OK] tray variable: found '{trayVar}'"

  # Step 3: Make the function async (if not already)
  if trayFunc != "":
    let oldFunc = "function " & trayFunc & "(){"
    let newFunc = "async function " & trayFunc & "(){"
    let asyncCheck = "async function " & trayFunc & "(){"
    if oldFunc in result and asyncCheck notin result:
      result = result.replace(oldFunc, newFunc)
      echo &"  [OK] async conversion: made {trayFunc}() async"
    elif asyncCheck in result:
      echo "  [INFO] async conversion: already async"
    else:
      echo "  [FAIL] async conversion: function pattern not found"
      failed = true

  # Step 4: Find first const variable in the function
  var firstConst = ""
  if trayFunc != "":
    let constPat = re2("async function " & trayFunc & "\\(\\)\\{.+?const (\\w+)=")
    for m in result.findAll(constPat):
      firstConst = result[m.group(0)]
      break

    if firstConst == "":
      echo "  [FAIL] first const in function: 0 matches"
      failed = true
    else:
      echo &"  [OK] first const in function: found '{firstConst}'"

  # Step 5: Add mutex guard
  if trayFunc != "" and firstConst != "":
    let mutexCheck = trayFunc & "._running"
    if mutexCheck notin result:
      let oldStart = "async function " & trayFunc & "(){"
      let mutexPrefix = "async function " & trayFunc & "(){if(" & trayFunc & "._running)return;" & trayFunc & "._running=true;setTimeout(()=>" & trayFunc & "._running=false,500);"
      if oldStart in result:
        result = result.replace(oldStart, mutexPrefix)
        echo "  [OK] mutex guard: added"
      else:
        echo "  [FAIL] mutex guard: insertion point not found"
        failed = true
    else:
      echo "  [INFO] mutex guard: already present"

  # Step 6: Add delay after Tray.destroy() for DBus cleanup
  if trayVar != "":
    let oldDestroy = trayVar & "&&(" & trayVar & ".destroy()," & trayVar & "=null)"
    let newDestroy = trayVar & "&&(" & trayVar & ".destroy()," & trayVar & "=null,await new Promise(r=>setTimeout(r,50)))"

    if oldDestroy in result and newDestroy notin result:
      result = result.replace(oldDestroy, newDestroy)
      echo &"  [OK] DBus cleanup delay: added after {trayVar}.destroy()"
    elif newDestroy in result:
      echo "  [INFO] DBus cleanup delay: already present"
    else:
      echo "  [FAIL] DBus cleanup delay: destroy pattern not found"
      failed = true

  if failed:
    raise newException(ValueError, "fix_tray_dbus: Some required patterns did not match")

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_tray_dbus <file>"
    quit(1)
  let file = paramStr(1)
  echo "=== Patch: fix_tray_dbus ==="
  echo &"  Target: {file}"
  if not fileExists(file):
    echo &"  [FAIL] File not found: {file}"
    quit(1)
  let input = readFile(file)
  let output = apply(input)
  if output != input:
    writeFile(file, output)
    echo "  [PASS] All required patterns matched and applied"
  else:
    echo "  [WARN] No changes made (patterns may have already been applied)"
