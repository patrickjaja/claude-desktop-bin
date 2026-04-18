# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
# Replace Windows-centric "VM service not running" errors with helpful
# Linux messages that guide users to install claude-cowork-service.

import std/[os, strformat, strutils]

const EXPECTED_PATCHES = 2

proc replaceOnce(s, sub, by: string): string =
  ## Replace only the first occurrence of `sub` with `by`.
  let idx = s.find(sub)
  if idx < 0: return s
  result = s[0 ..< idx] & by & s[idx + sub.len .. ^1]

proc apply*(input: string): string =
  result = input
  var patchesApplied = 0

  # Patch A: ENOENT / retry-exhausted error
  let oldA = "\"VM service not running. The service failed to start.\""
  let newA =
    "(process.platform===\"linux\"" &
    "?\"Cowork requires claude-cowork-service. " &
    "Install it from github.com/patrickjaja/claude-cowork-service, " &
    "then restart Claude Desktop.\"" &
    ":\"VM service not running. The service failed to start.\")"

  if oldA in result:
    result = result.replaceOnce(oldA, newA)
    echo "  [OK] Startup error message: replaced"
    patchesApplied += 1
  else:
    echo "  [WARN] Startup error message not found"

  # Patch B: Timeout fallback error
  let oldB = "throw new Error(\"VM service not running.\")"
  let newB =
    "throw new Error(process.platform===\"linux\"" &
    "?\"Cowork service not responding. " &
    "Make sure claude-cowork-service is running " &
    "(github.com/patrickjaja/claude-cowork-service), " &
    "then restart Claude Desktop.\"" &
    ":\"VM service not running.\")"

  if oldB in result:
    result = result.replaceOnce(oldB, newB)
    echo "  [OK] Timeout error message: replaced"
    patchesApplied += 1
  else:
    echo "  [WARN] Timeout error message not found"

  if patchesApplied < EXPECTED_PATCHES:
    raise newException(ValueError, &"fix_cowork_error_message: Only {patchesApplied}/{EXPECTED_PATCHES} patches applied")

  # Verify brace balance
  let originalDelta = input.count('{') - input.count('}')
  let patchedDelta = result.count('{') - result.count('}')
  if originalDelta != patchedDelta:
    let diff = patchedDelta - originalDelta
    raise newException(ValueError, &"fix_cowork_error_message: Patch introduced brace imbalance: {diff:+} unmatched braces")

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_cowork_error_message <file>"
    quit(1)
  let file = paramStr(1)
  echo "=== Patch: fix_cowork_error_message ==="
  echo &"  Target: {file}"
  if not fileExists(file):
    echo &"  [FAIL] File not found: {file}"
    quit(1)
  let input = readFile(file)
  let output = apply(input)
  if output == input:
    echo &"  [WARN] No changes made ({EXPECTED_PATCHES}/{EXPECTED_PATCHES} patterns matched but already applied)"
  else:
    writeFile(file, output)
    echo &"  [PASS] {EXPECTED_PATCHES} patches applied"
