# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
# Nim port of fix_quick_entry_ready_wayland.py

import std/[os, strformat, strutils, options]
import std/nre

proc apply*(input: string): string =
  var content = input

  let pat = re"""([\w$]+)\|\|await\(([\w$]+)==null\?void 0:\2\.catch\([\w$]+=>\{[\w$]+\.error\("Quick Entry: Error waiting for ready %o",\{error:[\w$]+\}\)\}\)\)"""
  let m = content.find(pat)
  if m.isSome:
    let mm = m.get
    let flagVar = mm.captures[0]
    let promiseVar = mm.captures[1]
    let old = mm.match
    let new = &"""{flagVar}||await Promise.race([{promiseVar}==null?void 0:{promiseVar}.catch(n=>{{R.error("Quick Entry: Error waiting for ready %o",{{error:n}})}}),new Promise(_r=>setTimeout(_r,200))])"""
    # Python replaces first occurrence
    let idx = content.find(old)
    if idx >= 0:
      content = content[0 ..< idx] & new & content[idx + old.len .. ^1]
    echo &"  [OK] ready-to-show timeout (200ms) added (vars: {flagVar}, {promiseVar})"
  else:
    raise newException(ValueError, "fix_quick_entry_ready_wayland: ready-to-show wait pattern not found")

  return content

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_quick_entry_ready_wayland <file>"
    quit(1)
  let file = paramStr(1)
  echo "=== Patch: fix_quick_entry_ready_wayland ==="
  echo &"  Target: {file}"
  let input = readFile(file)
  let output = apply(input)
  if output != input:
    writeFile(file, output)
  echo "  [PASS]"
