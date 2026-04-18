# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
#
# Fix UtilityProcess not terminating on app exit.
#
# When using the integrated Node.js server for MCP, the fallback kill
# after SIGTERM timeout sends another SIGTERM instead of SIGKILL,
# causing the process to remain alive and preventing app exit.
#
# Note: "utiltiy" and "proccess" are typos in the original Anthropic code.

import std/[os, strutils]
import regex

proc apply*(input: string): string =
  # Pattern: The setTimeout callback that tries to kill the UtilityProcess
  # after 5 seconds. Matches:
  #   const a=(s=this.process)==null?void 0:s.kill();te.info(`Killing utiltiy proccess again
  let pattern = re2"""(const \w+=\(\w+=this\.process\)==null\?void 0:\w+)(\.kill\(\))(;[\w$]+\.info\(`Killing utiltiy proccess again)"""
  var count = 0
  result = input.replace(pattern, proc(m: RegexMatch2, s: string): string =
    inc count
    # Replace .kill() with .kill("SIGKILL")
    s[m.group(0)] & """.kill("SIGKILL")""" & s[m.group(2)]
  )
  if count == 0:
    if "Killing utiltiy proccess again" in input:
      echo "  [INFO] Found 'Killing utiltiy proccess again' string in file"
    echo "  [FAIL] UtilityProcess kill pattern: 0 matches (may need pattern update)"
    quit(1)
  echo "  [OK] UtilityProcess SIGKILL fix: " & $count & " match(es)"

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_utility_process_kill <file>"
    quit(1)
  let filePath = paramStr(1)
  echo "=== Patch: fix_utility_process_kill ==="
  echo "  Target: " & filePath
  let input = readFile(filePath)
  let output = apply(input)
  writeFile(filePath, output)
  echo "  [PASS] UtilityProcess kill patched successfully"
