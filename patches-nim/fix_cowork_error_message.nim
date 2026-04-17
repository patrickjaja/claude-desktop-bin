# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
# Nim port of fix_cowork_error_message.py.

import std/[os, strformat, strutils]

proc apply*(input: string): string =
  var content = input
  let originalContent = input
  var patchesApplied = 0

  # Patch A: ENOENT / retry-exhausted error
  let oldA = "\"VM service not running. The service failed to start.\""
  let newA =
    "(process.platform===\"linux\"" &
    "?\"Cowork requires claude-cowork-service. " &
    "Install it from github.com/patrickjaja/claude-cowork-service, " &
    "then restart Claude Desktop.\"" &
    ":\"VM service not running. The service failed to start.\")"

  if content.contains(oldA):
    let idx = content.find(oldA)
    content = content[0 ..< idx] & newA & content[idx + oldA.len .. ^1]
    echo "  [OK] Startup error message: replaced"
    inc patchesApplied
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

  if content.contains(oldB):
    let idx = content.find(oldB)
    content = content[0 ..< idx] & newB & content[idx + oldB.len .. ^1]
    echo "  [OK] Timeout error message: replaced"
    inc patchesApplied
  else:
    echo "  [WARN] Timeout error message not found"

  const EXPECTED_PATCHES = 2
  if patchesApplied < EXPECTED_PATCHES:
    raise newException(ValueError,
      &"Only {patchesApplied}/{EXPECTED_PATCHES} patches applied — check [WARN]/[FAIL] messages above")

  if content == originalContent:
    echo &"  [WARN] No changes made ({patchesApplied}/{EXPECTED_PATCHES} patterns matched but already applied)"
    return content

  # Verify brace balance
  let originalDelta = originalContent.count('{') - originalContent.count('}')
  let patchedDelta = content.count('{') - content.count('}')
  if originalDelta != patchedDelta:
    let diff = patchedDelta - originalDelta
    raise newException(ValueError, &"Patch introduced brace imbalance: {diff:+d} unmatched braces")

  echo &"  [PASS] {patchesApplied} patches applied"
  result = content

when isMainModule:
  let file = paramStr(1)
  echo "=== Patch: fix_cowork_error_message ==="
  echo &"  Target: {file}"
  let input = readFile(file)
  let output = apply(input)
  if output != input:
    writeFile(file, output)
