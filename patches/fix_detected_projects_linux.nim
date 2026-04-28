# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
# Enable Detected Projects (Recent Projects) on Linux.
# Three patches: platform guard, VSCode/Cursor DB path, Zed DB path.

import std/[os, strformat, strutils]
import regex

proc apply*(input: string): string =
  result = input

  # Idempotency check
  if "process.platform!==\"linux\"" in result and "[detectedProjects]" in result:
    let idx = result.find("[detectedProjects] skipping")
    if idx != -1:
      let start = max(0, idx - 200)
      let nearby = result[start ..< idx]
      if "process.platform!==\"linux\"" in nearby:
        echo "  [SKIP] Already patched (linux platform guard found)"
        return result

  var allOk = true

  # 1. Platform guard in detection entry-point
  let patGuard =
    re2"(if\(process\.platform!==""darwin"")(&&process\.platform!==""linux"")?\)(return [\w$]+\.debug\(`\[detectedProjects\] skipping)"
  var countGuard = 0
  result = result.replace(
    patGuard,
    proc(m: RegexMatch2, s: string): string =
      inc countGuard
      s[m.group(0)] & "&&process.platform!==\"linux\")" & s[m.group(2)],
  )
  if countGuard > 0:
    echo &"  [OK] Platform guard: {countGuard} match(es)"
  else:
    echo "  [FAIL] Platform guard: 0 matches"
    allOk = false

  # 2. VSCode / Cursor state DB path
  let patVscode =
    re2"([\w$]+)\.join\(([\w$]+)\.homedir\(\),""Library"",""Application Support"",([\w$]+),""User"",""globalStorage"",""state\.vscdb""\)"
  var countVscode = 0
  result = result.replace(
    patVscode,
    proc(m: RegexMatch2, s: string): string =
      inc countVscode
      let p = s[m.group(0)]
      let o = s[m.group(1)]
      let d = s[m.group(2)]
      let mac =
        p & ".join(" & o & ".homedir(),\"Library\",\"Application Support\"," & d &
        ",\"User\",\"globalStorage\",\"state.vscdb\")"
      let lin =
        p & ".join(" & o & ".homedir(),\".config\"," & d &
        ",\"User\",\"globalStorage\",\"state.vscdb\")"
      "(process.platform===\"darwin\"?" & mac & ":" & lin & ")",
  )
  if countVscode > 0:
    echo &"  [OK] VSCode/Cursor DB path: {countVscode} match(es)"
  else:
    echo "  [FAIL] VSCode/Cursor DB path: 0 matches"
    allOk = false

  # 3. Zed state DB path
  let patZed =
    re2"([\w$]+)\.join\(([\w$]+)\.homedir\(\),""Library"",""Application Support"",""Zed"",""db"",""0-stable"",""db\.sqlite""\)"
  var countZed = 0
  result = result.replace(
    patZed,
    proc(m: RegexMatch2, s: string): string =
      inc countZed
      let p = s[m.group(0)]
      let o = s[m.group(1)]
      let mac =
        p & ".join(" & o &
        ".homedir(),\"Library\",\"Application Support\",\"Zed\",\"db\",\"0-stable\",\"db.sqlite\")"
      let lin =
        p & ".join(" & o &
        ".homedir(),\".local\",\"share\",\"zed\",\"db\",\"0-stable\",\"db.sqlite\")"
      "(process.platform===\"darwin\"?" & mac & ":" & lin & ")",
  )
  if countZed > 0:
    echo &"  [OK] Zed DB path: {countZed} match(es)"
  else:
    echo "  [FAIL] Zed DB path: 0 matches"
    allOk = false

  if not allOk:
    raise newException(
      ValueError, "fix_detected_projects_linux: Some patterns did not match"
    )

  if result == input:
    raise newException(ValueError, "fix_detected_projects_linux: No changes made")

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_detected_projects_linux <file>"
    quit(1)
  let file = paramStr(1)
  echo "=== Patch: fix_detected_projects_linux ==="
  echo &"  Target: {file}"
  if not fileExists(file):
    echo &"  [FAIL] File not found: {file}"
    quit(1)
  let input = readFile(file)
  let output = apply(input)
  if output != input:
    writeFile(file, output)
    echo "  [PASS] Detected Projects patched for Linux"
  else:
    echo "  [FAIL] No changes made"
    quit(1)
