# @patch-target: app.asar.contents/.vite/build/mainView.js
# @patch-type: nim
# Nim port of fix_process_argv_renderer.py.

import std/[os, strformat]
import regex

proc apply*(input: string): string =
  var content = input

  # Idempotency: already patched if any var.argv=[] appears
  let alreadyPat = re2"""[\w$]+\.argv=\[\]"""
  var hasAlready = false
  for _ in content.findAll(alreadyPat):
    hasAlready = true
    break
  if hasAlready:
    echo "  [OK] process.argv: already patched (skipped)"
    return content

  # Primary: before exposeInMainWorld("process",<var>)
  let expose = re2"""([\w$]+)\.contextBridge\.exposeInMainWorld\("process",([\w$]+)\)"""
  var m: RegexMatch2
  if find(content, expose, m):
    let varName = content[m.group(1)]
    let insertion = varName & ".argv=[];"
    content = content[0 ..< m.boundaries.a] & insertion & content[m.boundaries.a .. ^1]
    echo &"  [OK] process.argv: added {varName}.argv=[] (before exposeInMainWorld)"
    return content

  # Fallback 1: after platform spoof
  let spoof = re2"""([\w$]+)\.platform="win32"\}"""
  if find(content, spoof, m):
    let varName = content[m.group(0)]
    let insertion = varName & ".argv=[];"
    content = content[0 ..< m.boundaries.b + 1] & insertion & content[m.boundaries.b + 1 .. ^1]
    echo &"  [OK] process.argv: added {varName}.argv=[] (after platform spoof)"
    return content

  # Fallback 2: after .version=...appVersion;
  let ver = re2"""([\w$]+)\.version=[\w$]+\(\)\.appVersion;"""
  if find(content, ver, m):
    let varName = content[m.group(0)]
    let insertion = varName & ".argv=[];"
    content = content[0 ..< m.boundaries.b + 1] & insertion & content[m.boundaries.b + 1 .. ^1]
    echo &"  [OK] process.argv: added {varName}.argv=[] (after version)"
    return content

  echo "  [FAIL] process.argv: could not find insertion point"
  raise newException(ValueError, "fix_process_argv_renderer: insertion point not found")

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_process_argv_renderer <path_to_mainView.js>"
    quit(1)
  let file = paramStr(1)
  echo "=== Patch: fix_process_argv_renderer ==="
  echo &"  Target: {file}"
  let input = readFile(file)
  let output = apply(input)
  if output != input:
    writeFile(file, output)
