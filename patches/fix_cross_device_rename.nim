# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
#
# Fix cross-device rename errors on Linux.
#
# On Linux, /tmp is often a separate tmpfs filesystem. The app downloads VM
# bundles to /tmp and then tries fs.rename() to move them to ~/.config/Claude/.
# rename() fails with EXDEV when source and destination are on different
# filesystems.
#
# This patch replaces unguarded fs/promises rename calls with a cross-device-safe
# wrapper that falls back to copyFile+unlink when rename fails with EXDEV.

import std/[os, strutils]
import regex

proc apply*(input: string): string =
  # Replace each await <mod>.rename(x,y) call with an inline EXDEV-safe
  # fallback. The (?<!try\{) lookbehind skips rename calls already inside
  # a try block with their own EXDEV handler.
  #
  # Before: await ur.rename(x,y)
  # After:  await ur.rename(x,y).catch(async e=>{if(e.code==="EXDEV"){await ur.copyFile(x,y);await ur.unlink(x)}else throw e})
  let renamePattern = re2"""(?<!try\{)await ([\w$]+)\.rename\(([\w$]+),([\w$]+)\)"""
  var count = 0
  result = input.replace(
    renamePattern,
    proc(m: RegexMatch2, s: string): string =
      inc count
      let modVar = s[m.group(0)]
      let srcVar = s[m.group(1)]
      let dstVar = s[m.group(2)]
      "await " & modVar & ".rename(" & srcVar & "," & dstVar & ")" &
        """.catch(async e=>{if(e.code==="EXDEV"){""" & "await " & modVar & ".copyFile(" &
        srcVar & "," & dstVar & ");" & "await " & modVar & ".unlink(" & srcVar & ")" &
        "}else throw e})",
  )
  if count >= 1:
    echo "  [OK] Replaced " & $count & " rename() calls with inline EXDEV fallback"
  else:
    # Idempotency check: patched code contains the EXDEV catch marker.
    if """.catch(async e=>{if(e.code==="EXDEV"""" in input:
      echo "  [OK] Already patched (EXDEV catch marker present)"
      return input
    echo "  [FAIL] No unguarded rename() calls found and no EXDEV marker present"
    quit(1)

  if result == input:
    echo "  [FAIL] replace reported matches but content unchanged"
    quit(1)

  # Verify brace balance
  let originalDelta = input.count('{') - input.count('}')
  let patchedDelta = result.count('{') - result.count('}')
  if originalDelta != patchedDelta:
    let diff = patchedDelta - originalDelta
    echo "  [FAIL] Patch introduced brace imbalance: " & (if diff > 0: "+" else: "") &
      $diff
    quit(1)

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_cross_device_rename <path_to_index.js>"
    quit(1)
  let filePath = paramStr(1)
  echo "=== Patch: fix_cross_device_rename ==="
  echo "  Target: " & filePath
  if not fileExists(filePath):
    echo "  [FAIL] File not found: " & filePath
    quit(1)
  let input = readFile(filePath)
  let output = apply(input)
  writeFile(filePath, output)
  echo "  [PASS] Cross-device rename fix applied"
