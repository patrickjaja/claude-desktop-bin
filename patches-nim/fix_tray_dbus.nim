# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
# Nim port of fix_tray_dbus.py

import std/[os, strformat, strutils, options]
import std/nre

proc apply*(input: string): string =
  var content = input
  let original = input
  var failed = false

  # Step 1: Find the tray function name from menuBarEnabled listener
  let pat1 = re"""on\("menuBarEnabled",\(\)=>\{(\w+)\(\)\}\)"""
  let m1 = content.find(pat1)
  var trayFunc: string = ""
  if m1.isNone:
    echo "  [FAIL] menuBarEnabled listener: 0 matches, expected >= 1"
    failed = true
  else:
    trayFunc = m1.get.captures[0]
    echo &"  [OK] menuBarEnabled listener: found tray function '{trayFunc}'"

  # Step 2: Find tray variable name
  var trayVar: string = ""
  if trayFunc.len > 0:
    let pat2 = re("""let ([\w$]+)=null;(?:async )?function """ & trayFunc)
    let m2 = content.find(pat2)
    if m2.isNone:
      echo "  [FAIL] tray variable: 0 matches, expected >= 1"
      failed = true
    else:
      trayVar = m2.get.captures[0]
      echo &"  [OK] tray variable: found '{trayVar}'"

  # Step 3: Make the function async
  if trayFunc.len > 0:
    let oldFunc = "function " & trayFunc & "(){"
    let newFunc = "async function " & trayFunc & "(){"
    let asyncCheck = "async function " & trayFunc & "(){"
    if strutils.contains(content, oldFunc) and not strutils.contains(content, asyncCheck):
      content = content.replace(oldFunc, newFunc)
      echo &"  [OK] async conversion: made {trayFunc}() async"
    elif strutils.contains(content, asyncCheck):
      echo "  [INFO] async conversion: already async"
    else:
      echo "  [FAIL] async conversion: function pattern not found"
      failed = true

  # Step 4: Find first const in function body
  var firstConst: string = ""
  if trayFunc.len > 0:
    let pat4 = re("""async function """ & trayFunc & """\(\)\{[\s\S]+?const (\w+)=""")
    let m4 = content.find(pat4)
    if m4.isNone:
      echo "  [FAIL] first const in function: 0 matches"
      failed = true
    else:
      firstConst = m4.get.captures[0]
      echo &"  [OK] first const in function: found '{firstConst}'"

  # Step 5: Add mutex guard
  if trayFunc.len > 0 and firstConst.len > 0:
    let mutexCheck = trayFunc & "._running"
    if not strutils.contains(content, mutexCheck):
      let oldStart = "async function " & trayFunc & "(){"
      let mutexPrefix = "async function " & trayFunc & "(){if(" & trayFunc & "._running)return;" & trayFunc & "._running=true;setTimeout(()=>" & trayFunc & "._running=false,500);"
      if strutils.contains(content, oldStart):
        content = content.replace(oldStart, mutexPrefix)
        echo "  [OK] mutex guard: added"
      else:
        echo "  [FAIL] mutex guard: insertion point not found"
        failed = true
    else:
      echo "  [INFO] mutex guard: already present"

  # Step 6: Add delay after Tray.destroy()
  if trayVar.len > 0:
    let oldDestroy = trayVar & "&&(" & trayVar & ".destroy()," & trayVar & "=null)"
    let newDestroy = trayVar & "&&(" & trayVar & ".destroy()," & trayVar & "=null,await new Promise(r=>setTimeout(r,50)))"

    if strutils.contains(content, oldDestroy) and not strutils.contains(content, newDestroy):
      content = content.replace(oldDestroy, newDestroy)
      echo &"  [OK] DBus cleanup delay: added after {trayVar}.destroy()"
    elif strutils.contains(content, newDestroy):
      echo "  [INFO] DBus cleanup delay: already present"
    else:
      echo "  [FAIL] DBus cleanup delay: destroy pattern not found"
      failed = true

  if failed:
    raise newException(ValueError, "fix_tray_dbus: Some required patterns did not match")

  if content != original:
    echo "  [PASS] All required patterns matched and applied"
  else:
    echo "  [WARN] No changes made (patterns may have already been applied)"

  return content

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_tray_dbus <file>"
    quit(1)
  let file = paramStr(1)
  echo "=== Patch: fix_tray_dbus ==="
  echo &"  Target: {file}"
  let input = readFile(file)
  let output = apply(input)
  if output != input:
    writeFile(file, output)
  echo "  [PASS]"
