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

  # 2. Patch checkTrust bridge
  # v1.4758+: function body now starts with `const o=DQ(s);` before return N.info(...)
  let patCt = re2"(checkTrust\()([\w$]+)(\)\{)(const [\w$]+=[\w$]+\([\w$]+\);return [\w$]+\.info\()"
  var countCt = result.replaceFirst(
    patCt,
    proc(m: RegexMatch2, s: string): string =
      let arg = s[m.group(1)]
      s[m.group(0)] & arg & s[m.group(2)] & arg & "=__cdb_sanitizeCwd(" & arg & ");" &
        s[m.group(3)],
  )
  if countCt > 0:
    patchesApplied += countCt
    echo &"  [OK] checkTrust bridge: {countCt} match(es)"
  else:
    echo "  [WARN] checkTrust bridge: 0 matches"

  # 3. Patch saveTrust bridge
  # v1.4758+: function body now starts with `const o=DQ(s);` before N.info(...)
  let patSt = re2"(async saveTrust\()([\w$]+)(\)\{)(const [\w$]+=[\w$]+\([\w$]+\);[\w$]+\.info\()"
  var countSt = result.replaceFirst(
    patSt,
    proc(m: RegexMatch2, s: string): string =
      let arg = s[m.group(1)]
      s[m.group(0)] & arg & s[m.group(2)] & arg & "=__cdb_sanitizeCwd(" & arg & ");" &
        s[m.group(3)],
  )
  if countSt > 0:
    patchesApplied += countSt
    echo &"  [OK] saveTrust bridge: {countSt} match(es)"
  else:
    echo "  [WARN] saveTrust bridge: 0 matches"

  # 4. Patch start bridge
  let patStart =
    re2"(async start\()([\w$]+)(\)\{)(return [\w$]+\.info\(""LocalSessions\.start:""\))"
  var countStart = result.replaceFirst(
    patStart,
    proc(m: RegexMatch2, s: string): string =
      let arg = s[m.group(1)]
      s[m.group(0)] & arg & s[m.group(2)] & arg & ".cwd=__cdb_sanitizeCwd(" & arg &
        ".cwd);" & s[m.group(3)],
  )
  if countStart > 0:
    patchesApplied += countStart
    echo &"  [OK] start bridge: {countStart} match(es)"
  else:
    echo "  [WARN] start bridge: 0 matches"

  # 5. Patch startCodeSession bridges (conditional ternary form)
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
  if countScs > 0:
    patchesApplied += countScs
    echo &"  [OK] startCodeSession bridges: {countScs} match(es)"
  else:
    echo "  [WARN] startCodeSession bridges: 0 matches"

  # Also patch the dispatch startCodeSession (different signature)
  let patScs2 = re2"(startCodeSession:async\()([\w$]+)(,[\w$]+,[\w$]+,[\w$]+\)=>\{)"
  var countScs2 = 0
  result = result.replace(
    patScs2,
    proc(m: RegexMatch2, s: string): string =
      inc countScs2
      let arg = s[m.group(1)]
      s[m.group(0)] & arg & s[m.group(2)] & arg & "=__cdb_sanitizeCwd(" & arg & ");",
  )
  if countScs2 > 0:
    patchesApplied += countScs2
    echo &"  [OK] dispatch startCodeSession: {countScs2} match(es)"
  else:
    echo "  [WARN] dispatch startCodeSession: 0 matches"

  if patchesApplied < EXPECTED_PATCHES:
    raise newException(
      ValueError,
      &"fix_asar_workspace_cwd: Only {patchesApplied}/{EXPECTED_PATCHES} patches applied",
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
