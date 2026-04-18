# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
# Fix paths that use process.resourcesPath + "app.asar" on Linux.
# Two fixes: nodeHostPath and shellPathWorker.
# Uses std/nre for backreference support in patterns.

import std/[os, strformat, options]
import std/nre
from std/strutils import nil

proc apply*(input: string): string =
  result = input

  # Patch 1: nodeHostPath -- replace entire ternary with app.getAppPath()
  # Pattern uses \2 backreference for path var reuse
  let pattern1 = re"""this\.nodeHostPath=([\w$]+)\.app\.isPackaged\?([\w$]+)\.join\(process\.resourcesPath,"app\.asar","\.vite","build","mcp-runtime","nodeHost\.js"\):\2\.join\(\1\.app\.getAppPath\(\),"\.vite","build","mcp-runtime","nodeHost\.js"\)"""

  let m1 = result.find(pattern1)
  if m1.isSome:
    let m = m1.get
    let electronVar = m.captures[0]
    let pathVar = m.captures[1]
    let replacement = "this.nodeHostPath=" & pathVar & ".join(" & electronVar & ".app.getAppPath(),\".vite\",\"build\",\"mcp-runtime\",\"nodeHost.js\")"
    result = result[0 ..< m.matchBounds.a] & replacement & result[m.matchBounds.b + 1 .. ^1]
    echo "  [OK] nodeHostPath: 1 match(es)"
  else:
    echo "  [FAIL] nodeHostPath: 0 matches, expected 1"
    echo "  This patch must run BEFORE fix_locale_paths.py (on original code)"
    raise newException(ValueError, "fix_0_node_host: nodeHostPath pattern not found")

  # Patch 2: shellPathWorker -- replace process.resourcesPath,"app.asar" with app.getAppPath()
  let pattern2 = re"""(function [\w$]+\(\)\{return )([\w$]+)(\.join\()process\.resourcesPath,"app\.asar",("\.vite","build","shell-path-worker","shellPathWorker\.js"\))"""

  let m2 = result.find(pattern2)
  if m2.isSome:
    let m = m2.get
    let replacement = m.captures[0] & m.captures[1] & m.captures[2] & "require(\"electron\").app.getAppPath()," & m.captures[3]
    result = result[0 ..< m.matchBounds.a] & replacement & result[m.matchBounds.b + 1 .. ^1]
    echo "  [OK] shellPathWorker: 1 match(es)"
  else:
    # Idempotency check
    if strutils.find(result, "require(\"electron\").app.getAppPath(),\".vite\",\"build\",\"shell-path-worker\"") >= 0:
      echo "  [OK] shellPathWorker: already patched"
    else:
      echo "  [FAIL] shellPathWorker: 0 matches and no already-patched marker"
      raise newException(ValueError, "fix_0_node_host: shellPathWorker pattern not found")

  if result == input:
    echo "  [WARN] No changes made"

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_0_node_host <file>"
    quit(1)
  let file = paramStr(1)
  echo "=== Patch: fix_0_node_host ==="
  echo &"  Target: {file}"
  if not fileExists(file):
    echo &"  [FAIL] File not found: {file}"
    quit(1)
  let input = readFile(file)
  let output = apply(input)
  if output != input:
    writeFile(file, output)
    echo "  [PASS] Node host path patched successfully"
  else:
    echo "  [WARN] No changes made"
