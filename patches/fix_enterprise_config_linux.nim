# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
#
# Enable enterprise config on Linux.
#
# The enterprise config function reads managed configuration:
# - macOS: reads from CFPreferences (MDM profiles)
# - Windows: reads from Windows Registry (Group Policy)
# - Linux: returns {} (no enterprise config support)
#
# This patch adds Linux support by reading from a JSON file at
# /etc/claude-desktop/enterprise.json. If the file doesn't exist
# or is invalid, falls back to {} (preserving current behavior).

import std/[os, strutils]
import regex

const linuxReader =
  """process.platform==="linux"?(()=>{try{return JSON.parse(require("fs").readFileSync("/etc/claude-desktop/enterprise.json","utf8"))}catch(e){return{}}})():{}"""

proc apply*(input: string): string =
  # Idempotency check: skip if already patched
  if "/etc/claude-desktop/enterprise.json" in input:
    echo "  [OK] Already patched (enterprise.json path found)"
    echo "  [PASS] No changes needed"
    return input

  # Pattern: the ternary chain in enterprise config loader functions.
  #
  # Original:
  #   process.platform==="darwin"?FUNC_D():process.platform==="win32"?FUNC_W():{}
  #
  # Patched -- add Linux branch before the fallback {}:
  #   process.platform==="darwin"?FUNC_D():process.platform==="win32"?FUNC_W():
  #     process.platform==="linux"?(...)():{}
  let pattern =
    re2"""process\.platform==="darwin"\?([\w$]+)\(\):process\.platform==="win32"\?([\w$]+)\(\):\{\}"""
  var count = 0
  result = input.replace(
    pattern,
    proc(m: RegexMatch2, s: string): string =
      inc count
      let darwinFn = s[m.group(0)]
      let win32Fn = s[m.group(1)]
      """process.platform==="darwin"?""" & darwinFn &
        """():process.platform==="win32"?""" & win32Fn & "():" & linuxReader,
  )
  if count >= 1:
    echo "  [OK] Enterprise config Linux reader: " & $count & " match(es)"
  else:
    echo "  [FAIL] Enterprise config default case: 0 matches"
    quit(1)

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_enterprise_config_linux <path_to_index.js>"
    quit(1)
  let filePath = paramStr(1)
  echo "=== Patch: fix_enterprise_config_linux ==="
  echo "  Target: " & filePath
  if not fileExists(filePath):
    echo "  [FAIL] File not found: " & filePath
    quit(1)
  let input = readFile(filePath)
  let output = apply(input)
  if output != input:
    writeFile(filePath, output)
  echo "  [PASS] Enterprise config Linux support added"

  # Also patch index.pre.js if it exists (early bootstrap enterprise config)
  let preJs = parentDir(filePath) / "index.pre.js"
  if fileExists(preJs):
    let preContent = readFile(preJs)
    if "/etc/claude-desktop/enterprise.json" in preContent:
      echo "  [OK] index.pre.js: already patched"
    else:
      let prePattern =
        re2"""process\.platform==="darwin"\?([\w$]+)\(\):process\.platform==="win32"\?([\w$]+)\(\):\{\}"""
      var preCount = 0
      let newPreContent = preContent.replace(
        prePattern,
        proc(m: RegexMatch2, s: string): string =
          inc preCount
          let darwinFn = s[m.group(0)]
          let win32Fn = s[m.group(1)]
          """process.platform==="darwin"?""" & darwinFn &
            """():process.platform==="win32"?""" & win32Fn & "():" & linuxReader,
      )
      if preCount >= 1:
        writeFile(preJs, newPreContent)
        echo "  [OK] index.pre.js: enterprise config patched (" & $preCount & " match)"
      else:
        echo "  [INFO] index.pre.js: no matching pattern (optional)"
