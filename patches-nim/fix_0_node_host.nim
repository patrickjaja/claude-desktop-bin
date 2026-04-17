# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
# Nim port of fix_0_node_host.py
# Uses std/nre because pat1 has \1 and \2 backreferences in the pattern.

import std/[os, strformat, strutils]
import std/nre

proc apply*(input: string): string =
  var content = input
  let original = input

  # Patch 1: nodeHostPath — replace ternary with app.getAppPath()
  let pat1 = re"""this\.nodeHostPath=([\w$]+)\.app\.isPackaged\?([\w$]+)\.join\(process\.resourcesPath,"app\.asar","\.vite","build","mcp-runtime","nodeHost\.js"\):\2\.join\(\1\.app\.getAppPath\(\),"\.vite","build","mcp-runtime","nodeHost\.js"\)"""
  var count1 = 0
  content = content.replace(pat1, proc (m: RegexMatch): string =
    inc count1
    let electronVar = m.captures[0]
    let pathVar = m.captures[1]
    "this.nodeHostPath=" & pathVar & ".join(" & electronVar & ".app.getAppPath(),\".vite\",\"build\",\"mcp-runtime\",\"nodeHost.js\")"
  )
  if count1 > 0:
    echo &"  [OK] nodeHostPath: {count1} match(es)"
  else:
    echo "  [FAIL] nodeHostPath: 0 matches, expected 1"
    raise newException(ValueError, "fix_0_node_host: nodeHostPath pattern not found")

  # Patch 2: shellPathWorker
  let pat2 = re"""(function [\w$]+\(\)\{return )([\w$]+)(\.join\()process\.resourcesPath,"app\.asar",("\.vite","build","shell-path-worker","shellPathWorker\.js"\))"""
  var count2 = 0
  content = content.replace(pat2, proc (m: RegexMatch): string =
    inc count2
    m.captures[0] & m.captures[1] & m.captures[2] & "require(\"electron\").app.getAppPath()," & m.captures[3]
  )
  if count2 > 0:
    echo &"  [OK] shellPathWorker: {count2} match(es)"
  else:
    if content.contains("require(\"electron\").app.getAppPath(),\"\\.vite\",\"build\",\"shell-path-worker\"") or
       content.contains("require(\"electron\").app.getAppPath(),\".vite\",\"build\",\"shell-path-worker\""):
      echo "  [OK] shellPathWorker: already patched"
    else:
      echo "  [FAIL] shellPathWorker: 0 matches and no already-patched marker"
      raise newException(ValueError, "fix_0_node_host: shellPathWorker pattern not found")

  result = content

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_0_node_host <file>"
    quit(1)
  let file = paramStr(1)
  echo "=== Patch: fix_0_node_host ==="
  echo &"  Target: {file}"
  let input = readFile(file)
  let output = apply(input)
  if output != input:
    writeFile(file, output)
    echo "  [PASS] Node host path patched successfully"
  else:
    echo "  [WARN] No changes made"
