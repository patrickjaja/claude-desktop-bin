# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
# Nim port of fix_window_bounds.py

import std/[os, strformat, strutils, options]
import std/nre

const BOUNDS_FIX_JS = (
  "(function(__wb_w){" &
  "if(process.platform!==\"linux\")return;" &
  "var __wb_fcb=function(){" &
  "if(__wb_w.isDestroyed())return;" &
  "var __wb_cv=__wb_w.contentView;" &
  "if(!__wb_cv||!__wb_cv.children||!__wb_cv.children.length)return;" &
  "var __wb_cs=__wb_w.getContentSize(),__wb_cw=__wb_cs[0],__wb_ch=__wb_cs[1];" &
  "if(__wb_cw<=0||__wb_ch<=0)return;" &
  "var __wb_cb=__wb_cv.children[0].getBounds();" &
  "if(__wb_cb.width!==__wb_cw||__wb_cb.height!==__wb_ch)" &
  "__wb_cv.children[0].setBounds({x:0,y:0,width:__wb_cw,height:__wb_ch})" &
  "};" &
  "var __wb_fasc=function(){__wb_fcb();setTimeout(__wb_fcb,16);setTimeout(__wb_fcb,150)};" &
  "[\"maximize\",\"unmaximize\",\"enter-full-screen\",\"leave-full-screen\"]" &
  ".forEach(function(__wb_ev){__wb_w.on(__wb_ev,__wb_fasc)});" &
  "var __wb_lsz=[0,0];" &
  "__wb_w.on(\"moved\",function(){" &
  "if(__wb_w.isDestroyed())return;" &
  "var __wb_s=__wb_w.getSize();" &
  "if(__wb_s[0]!==__wb_lsz[0]||__wb_s[1]!==__wb_lsz[1])" &
  "{__wb_lsz=__wb_s;__wb_fasc()}" &
  "});" &
  "__wb_w.once(\"ready-to-show\",function(){" &
  "var __wb_s=__wb_w.getSize();" &
  "__wb_w.setSize(__wb_s[0]+1,__wb_s[1]+1);" &
  "setTimeout(function(){" &
  "if(__wb_w.isDestroyed())return;" &
  "__wb_w.setSize(__wb_s[0],__wb_s[1]);" &
  "__wb_fasc()" &
  "},50)" &
  "})" &
  "})"
)

proc apply*(input: string): string =
  var content = input
  let original = input
  var applied: seq[string] = @[]

  # --- 1. Child view bounds fix + ready-to-show jiggle ---
  let boundsMarker = "__wb_fcb"
  if strutils.contains(content, boundsMarker):
    echo "  [INFO] Window bounds fix already injected"
    applied.add("bounds-fix(skip)")
  else:
    let mainWinPattern = re"""(function [\w$]+\([\w$]+\)\{return )([\w$]+)=new ([\w$]+)\.BrowserWindow\(([\w$]+)\),([\w$]+\(\2\.webContents,[\w$]+\.MAIN_WINDOW\)),\2\}"""
    var count = 0
    content = content.replace(mainWinPattern, proc (m: RegexMatch): string =
      inc count
      let prefix = m.captures[0]
      let winVar = m.captures[1]
      let electronVar = m.captures[2]
      let paramVar = m.captures[3]
      let setupCall = m.captures[4]
      let iife = BOUNDS_FIX_JS & "(" & winVar & ")"
      prefix & winVar & "=new " & electronVar & ".BrowserWindow(" & paramVar & ")," & setupCall & "," & iife & "," & winVar & "}"
    )
    if count > 0:
      echo &"  [OK] Window bounds fix + size jiggle injected: {count} match(es)"
      applied.add(&"bounds-fix({count})")
    else:
      echo "  [FAIL] Main window factory pattern not matched"
      raise newException(ValueError, "fix_window_bounds: Main window factory pattern not matched")

  # --- 2. Quick Entry blur before hide ---
  let qeBlurCheck = re"""[\w$]+\.blur\(\),[\w$]+\.hide\(\)"""
  if content.find(qeBlurCheck).isSome:
    echo "  [INFO] Quick Entry blur already applied"
    applied.add("qe-blur(skip)")
  else:
    let qeHidePattern = re"""(function [\w$]+\(\)\{)([\w$]+\(\))\|\|([\w$]+)(\.hide\(\))\}"""
    var count = 0
    content = content.replace(qeHidePattern, proc (m: RegexMatch): string =
      inc count
      let funcDecl = m.captures[0]
      let guardCall = m.captures[1]
      let winVar = m.captures[2]
      let hideCall = m.captures[3]
      funcDecl & guardCall & "||(" & winVar & ".blur()," & winVar & hideCall & ")}"
    )
    if count > 0:
      echo &"  [OK] Quick Entry blur before hide: {count} match(es)"
      applied.add(&"qe-blur({count})")
    else:
      echo "  [FAIL] Quick Entry hide pattern not matched"
      raise newException(ValueError, "fix_window_bounds: Quick Entry hide pattern not matched")

  if applied.len == 0:
    raise newException(ValueError, "fix_window_bounds: No patches could be applied")

  if content != original:
    echo &"  [PASS] Applied: {applied.join(\", \")}"
  else:
    echo "  [PASS] No changes needed (already patched)"

  return content

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_window_bounds <file>"
    quit(1)
  let file = paramStr(1)
  echo "=== Patch: fix_window_bounds ==="
  echo &"  Target: {file}"
  let input = readFile(file)
  let output = apply(input)
  if output != input:
    writeFile(file, output)
  echo "  [PASS]"
