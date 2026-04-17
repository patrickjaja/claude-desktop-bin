# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
# Nim port of fix_detected_projects_linux.py

import std/[os, strformat, strutils]
import regex

proc apply*(input: string): string =
  var content = input
  let original = input

  # Idempotency check: if linux guard already present near the skipping log message
  if content.contains("process.platform!==\"linux\"") and content.contains("[detectedProjects]"):
    let marker = "[detectedProjects] skipping"
    let idx = content.find(marker)
    if idx != -1:
      let lo = max(0, idx - 200)
      let nearby = content[lo ..< idx]
      if nearby.contains("process.platform!==\"linux\""):
        echo "  [SKIP] Already patched (linux platform guard found)"
        return content

  var allOk = true

  # 1. Platform guard
  let patGuard = re2"""(if\(process\.platform!=="darwin")(\)return [\w$]+\.debug\(`\[detectedProjects\] skipping)"""
  var cGuard = 0
  content = content.replace(patGuard, proc (m: RegexMatch2, s: string): string =
    inc cGuard
    let g1 = s[m.group(0)]
    let g2 = s[m.group(1)]
    g1 & "&&process.platform!==\"linux\"" & g2
  )
  if cGuard > 0:
    echo &"  [OK] Platform guard: {cGuard} match(es)"
  else:
    echo "  [FAIL] Platform guard: 0 matches"
    allOk = false

  # 2. VSCode / Cursor state DB path
  let patVscode = re2"""([\w$]+)\.join\(([\w$]+)\.homedir\(\),"Library","Application Support",([\w$]+),"User","globalStorage","state\.vscdb"\)"""
  var cVscode = 0
  content = content.replace(patVscode, proc (m: RegexMatch2, s: string): string =
    inc cVscode
    let p = s[m.group(0)]
    let o = s[m.group(1)]
    let d = s[m.group(2)]
    let mac = p & ".join(" & o & ".homedir(),\"Library\",\"Application Support\"," & d & ",\"User\",\"globalStorage\",\"state.vscdb\")"
    let lin = p & ".join(" & o & ".homedir(),\".config\"," & d & ",\"User\",\"globalStorage\",\"state.vscdb\")"
    "(process.platform===\"darwin\"?" & mac & ":" & lin & ")"
  )
  if cVscode > 0:
    echo &"  [OK] VSCode/Cursor DB path: {cVscode} match(es)"
  else:
    echo "  [FAIL] VSCode/Cursor DB path: 0 matches"
    allOk = false

  # 3. Zed state DB path
  let patZed = re2"""([\w$]+)\.join\(([\w$]+)\.homedir\(\),"Library","Application Support","Zed","db","0-stable","db\.sqlite"\)"""
  var cZed = 0
  content = content.replace(patZed, proc (m: RegexMatch2, s: string): string =
    inc cZed
    let p = s[m.group(0)]
    let o = s[m.group(1)]
    let mac = p & ".join(" & o & ".homedir(),\"Library\",\"Application Support\",\"Zed\",\"db\",\"0-stable\",\"db.sqlite\")"
    let lin = p & ".join(" & o & ".homedir(),\".local\",\"share\",\"zed\",\"db\",\"0-stable\",\"db.sqlite\")"
    "(process.platform===\"darwin\"?" & mac & ":" & lin & ")"
  )
  if cZed > 0:
    echo &"  [OK] Zed DB path: {cZed} match(es)"
  else:
    echo "  [FAIL] Zed DB path: 0 matches"
    allOk = false

  if content != original:
    if allOk:
      discard
    else:
      raise newException(ValueError, "fix_detected_projects_linux: partial patch")
  else:
    echo "  [FAIL] No changes made"
    raise newException(ValueError, "fix_detected_projects_linux: no changes made")

  result = content

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_detected_projects_linux <file>"
    quit(1)
  let file = paramStr(1)
  echo "=== Patch: fix_detected_projects_linux ==="
  echo &"  Target: {file}"
  let input = readFile(file)
  let output = apply(input)
  if output != input:
    writeFile(file, output)
    echo "  [PASS] Detected Projects patched for Linux"
  else:
    echo "  [WARN] No changes made"
