# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
# Prevent 'app.asar' from being used as workspace directory on Linux.
# Sanitizes workspace paths at the IPC bridge layer.

import std/[os, strformat, strutils]
import regex

const EXPECTED_PATCHES = 5

proc replaceFirst(
    content: var string, pattern: Regex2, subFn: proc(m: RegexMatch2, s: string): string
): int =
  var found = false
  var resultStr = ""
  var lastEnd = 0
  for m in content.findAll(pattern):
    if not found:
      let bounds = m.boundaries
      resultStr &= content[lastEnd ..< bounds.a]
      resultStr &= subFn(m, content)
      lastEnd = bounds.b + 1
      found = true
      break
  if found:
    resultStr &= content[lastEnd .. ^1]
    content = resultStr
    return 1
  return 0

proc apply*(input: string): string =
  result = input

  # Idempotency check
  if "__cdb_sanitizeCwd" in result:
    echo "  [SKIP] Already patched (__cdb_sanitizeCwd found)"
    return result

  var patchesApplied = 0

  # 1. Inject helper function
  const SANITIZE_FN =
    "var __cdb_sanitizeCwd=function(p){if(process.platform===\"linux\"&&typeof p===\"string\"&&/app\\.asar/.test(p)){return require(\"os\").homedir()}return p};"

  let useStrict = "\"use strict\";"
  let idx = result.find(useStrict)
  if idx >= 0:
    let injectPoint = idx + useStrict.len
    result = result[0 ..< injectPoint] & SANITIZE_FN & result[injectPoint .. ^1]
    echo "  [OK] Injected __cdb_sanitizeCwd helper (after 'use strict')"
  else:
    result = SANITIZE_FN & result
    echo "  [OK] Injected __cdb_sanitizeCwd helper (at file start)"

  # Each of the 5 bridge sites below must match EXACTLY ONCE. We assert per-site
  # counts and fail loud on any miss — we do NOT sum match counts into a single
  # `>= EXPECTED_PATCHES` threshold. Summing is unsafe here because sites 5 and 6
  # use unbounded `replace` (count can be >1): an over-match at one site could mask
  # a zero-match at another and still clear the threshold, shipping an unsanitized
  # cwd bridge (app.asar usable as a Cowork workspace dir). Per-site exact-count
  # guards make every bridge independently verified.
  proc requireExactlyOne(siteName: string, count: int) =
    if count == 1:
      patchesApplied += 1
      echo &"  [OK] {siteName}: 1 match"
    else:
      raise newException(
        ValueError,
        &"fix_asar_workspace_cwd: {siteName}: expected exactly 1 match, got {count} — upstream may have refactored this bridge; re-audit",
      )

  # 2. Patch checkTrust bridge
  let patCt = re2"(checkTrust\()([\w$]+)(\)\{)"
  let countCt = result.replaceFirst(
    patCt,
    proc(m: RegexMatch2, s: string): string =
      let arg = s[m.group(1)]
      s[m.group(0)] & arg & s[m.group(2)] & arg & "=__cdb_sanitizeCwd(" & arg & ");",
  )
  requireExactlyOne("checkTrust bridge", countCt)

  # 3. Patch saveTrust bridge
  let patSt = re2"(async saveTrust\()([\w$]+)(\)\{)"
  let countSt = result.replaceFirst(
    patSt,
    proc(m: RegexMatch2, s: string): string =
      let arg = s[m.group(1)]
      s[m.group(0)] & arg & s[m.group(2)] & arg & "=__cdb_sanitizeCwd(" & arg & ");",
  )
  requireExactlyOne("saveTrust bridge", countSt)

  # 4. Patch start bridge
  let patStart =
    re2"(async start\()([\w$]+)(\)\{)([\w$]+\.info\(""LocalSessions\.start:""\))"
  let countStart = result.replaceFirst(
    patStart,
    proc(m: RegexMatch2, s: string): string =
      let arg = s[m.group(1)]
      s[m.group(0)] & arg & s[m.group(2)] & arg & ".cwd=__cdb_sanitizeCwd(" & arg &
        ".cwd);" & s[m.group(3)],
  )
  requireExactlyOne("start bridge", countStart)

  # 5. Patch startCodeSession bridge (conditional ternary form)
  let patScs =
    re2"(startCodeSession:[\w$]+\?async\()([\w$]+)(,[\w$]+,[\w$]+,[\w$]+\)=>\{)"
  var countScs = 0
  result = result.replace(
    patScs,
    proc(m: RegexMatch2, s: string): string =
      inc countScs
      let arg = s[m.group(1)]
      s[m.group(0)] & arg & s[m.group(2)] & arg & "=__cdb_sanitizeCwd(" & arg & ");",
  )
  requireExactlyOne("startCodeSession bridge (ternary)", countScs)

  # 6. Patch the dispatch startCodeSession bridge (different signature)
  let patScs2 = re2"(startCodeSession:async\()([\w$]+)(,[\w$]+,[\w$]+,[\w$]+\)=>\{)"
  var countScs2 = 0
  result = result.replace(
    patScs2,
    proc(m: RegexMatch2, s: string): string =
      inc countScs2
      let arg = s[m.group(1)]
      s[m.group(0)] & arg & s[m.group(2)] & arg & "=__cdb_sanitizeCwd(" & arg & ");",
  )
  requireExactlyOne("dispatch startCodeSession bridge", countScs2)

  if patchesApplied != EXPECTED_PATCHES:
    raise newException(
      ValueError,
      &"fix_asar_workspace_cwd: {patchesApplied}/{EXPECTED_PATCHES} sites patched (expected all distinct)",
    )

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_asar_workspace_cwd <file>"
    quit(1)
  let file = paramStr(1)
  echo "=== Patch: fix_asar_workspace_cwd ==="
  echo &"  Target: {file}"
  if not fileExists(file):
    echo &"  [FAIL] File not found: {file}"
    quit(1)
  let input = readFile(file)
  let output = apply(input)
  if output == input:
    echo "  [OK] All patches already applied (no changes needed)"
  else:
    writeFile(file, output)
    echo "  [PASS] Patches applied"
