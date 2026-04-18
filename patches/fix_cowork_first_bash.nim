# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
# Fix first bash command returning empty output in Cowork sessions.
# Adds poll-wait for events socket before first spawn command.
# Uses std/nre for backreference support in patterns.

import std/[os, strformat, strutils, options]
import std/nre

proc apply*(input: string): string =
  result = input

  # Check idempotency
  if "_cdb_evsock_wait" in result:
    echo "  [OK] A events socket wait: already patched (skipped)"
    return result

  # Step 1: find the events socket variable name
  let evSockPat = re"function ([\w$]+)\(\)\{if\(([\w$]+)\)return;const [\w$]+=[\w$]+\.createConnection"
  let evSockMatch = result.find(evSockPat)
  if evSockMatch.isNone:
    echo "  [FAIL] A events socket wait: cannot find events socket function"
    raise newException(ValueError, "fix_cowork_first_bash: events socket function not found")

  let evVar = evSockMatch.get.captures[1]

  # Step 2: match the spawn preamble using backreference \3
  let spawnPattern = re"""([\w$]+\(\),await [\w$]+\(\))(;const ([\w$]+)=await [\w$]+\(\);if\(!\3\)throw new Error\("VM is not available)"""

  let spawnMatch = result.find(spawnPattern)
  if spawnMatch.isNone:
    echo "  [FAIL] A events socket wait: spawn pattern not found"
    raise newException(ValueError, "fix_cowork_first_bash: spawn pattern not found")

  let m = spawnMatch.get
  let waitCode =
    ";/* _cdb_evsock_wait */" &
    "if(typeof " & evVar & "===\"undefined\"||!" & evVar & ")" &
    "await new Promise(function(_r){" &
    "var _c=0,_iv=setInterval(function(){" &
    "if((typeof " & evVar & "!==\"undefined\"&&" & evVar & ")||++_c>200){clearInterval(_iv);_r()}" &
    "},10)})"

  let replacement = m.captures[0] & waitCode & m.captures[1]
  result = result[0 ..< m.matchBounds.a] & replacement & result[m.matchBounds.b + 1 .. ^1]
  echo &"  [OK] A events socket wait: injected {evVar} poll-wait before spawn"

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_cowork_first_bash <file>"
    quit(1)
  let file = paramStr(1)
  echo "=== Patch: fix_cowork_first_bash ==="
  echo &"  Target: {file}"
  if not fileExists(file):
    echo &"  [FAIL] File not found: {file}"
    quit(1)
  let input = readFile(file)
  let output = apply(input)
  if output != input:
    writeFile(file, output)
    echo "  [PASS] First bash command race condition fixed"
  else:
    echo "  [OK] Already patched, no changes needed"
