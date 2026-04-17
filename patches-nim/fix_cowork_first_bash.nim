# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
# Nim port of fix_cowork_first_bash.py — has backrefs, uses std/nre.

import std/[os, strformat, strutils, options]
import std/nre

proc apply*(input: string): string =
  var content = input
  let originalContent = input
  var patchesApplied = 0
  const EXPECTED_PATCHES = 1

  # Step 1: find the events socket variable name
  # Pattern: function FUNC(){if(VAR)return;...createConnection...subscribeEvents
  let evSockRe = re"""function ([\w$]+)\(\)\{if\(([\w$]+)\)return;const [\w$]+=[\w$]+\.createConnection"""
  let evSockMatch = content.find(evSockRe)
  if evSockMatch.isNone:
    echo "  [FAIL] A events socket wait: cannot find events socket function"
  else:
    let evVar = evSockMatch.get.captures[1]

    # Step 2: match the spawn preamble using regex
    let spawnPat = re"""([\w$]+\(\),await [\w$]+\(\))(;const ([\w$]+)=await [\w$]+\(\);if\(!\3\)throw new Error\("VM is not available)"""

    let alreadyA = content.contains("_cdb_evsock_wait")
    if alreadyA:
      echo "  [OK] A events socket wait: already patched (skipped)"
      inc patchesApplied
    else:
      let spawnMatch = content.find(spawnPat)
      if spawnMatch.isSome:
        let mm = spawnMatch.get
        let waitCode =
          ";/* _cdb_evsock_wait */" &
          "if(typeof " & evVar & "===\"undefined\"||!" & evVar & ")" &
          "await new Promise(function(_r){" &
          "var _c=0,_iv=setInterval(function(){" &
          "if((typeof " & evVar & "!==\"undefined\"&&" & evVar & ")||++_c>200){clearInterval(_iv);_r()}" &
          "},10)})"
        let oldFull = mm.match
        let newFull = mm.captures[0] & waitCode & mm.captures[1]
        # Use replace once like Python's replace(old, new, 1)
        let idx = content.find(oldFull)
        content = content[0 ..< idx] & newFull & content[idx + oldFull.len .. ^1]
        echo &"  [OK] A events socket wait: injected {evVar} poll-wait before spawn"
        inc patchesApplied
      else:
        echo "  [FAIL] A events socket wait: spawn pattern not found"

  if patchesApplied < EXPECTED_PATCHES:
    raise newException(ValueError, &"Only {patchesApplied}/{EXPECTED_PATCHES} patches applied")

  if content != originalContent:
    echo "  [PASS] First bash command race condition fixed"
  else:
    echo "  [OK] Already patched, no changes needed"
  result = content

when isMainModule:
  let file = paramStr(1)
  echo "=== Patch: fix_cowork_first_bash ==="
  echo &"  Target: {file}"
  let input = readFile(file)
  let output = apply(input)
  if output != input:
    writeFile(file, output)
