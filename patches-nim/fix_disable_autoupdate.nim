# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
# Nim port of fix_disable_autoupdate.py.

import std/[os, strformat]
import regex

proc apply*(input: string): string =
  # Pattern: function XXX(){...if(process.platform!=="win32")return YY.app.isPackaged
  # Insert: if(process.platform==="linux")return!1; at function body start.
  let pattern = re2"""(function [\w$]+\(\)\{)((?:if\([\w$]+\.forceInstalled\)return!0;)?if\(process\.platform!=="win32"\)return [\w$]+\.app\.isPackaged)"""
  var count = 0
  result = input.replace(pattern, proc (m: RegexMatch2, s: string): string =
    inc count
    let g1 = s[m.group(0)]
    let g2 = s[m.group(1)]
    g1 & "if(process.platform===\"linux\")return!1;" & g2
  )
  if count >= 1:
    echo &"  [OK] isInstalled Linux gate: {count} match(es)"
  else:
    echo "  [FAIL] isInstalled function: 0 matches"
    raise newException(ValueError, "fix_disable_autoupdate: required pattern not found")

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_disable_autoupdate <path_to_index.js>"
    quit(1)
  let file = paramStr(1)
  echo "=== Patch: fix_disable_autoupdate ==="
  echo &"  Target: {file}"
  let input = readFile(file)
  let output = apply(input)
  if output != input:
    writeFile(file, output)
    echo "  [PASS] Auto-updater disabled on Linux"
  else:
    echo "  [WARN] No changes made (pattern may have already been applied)"
