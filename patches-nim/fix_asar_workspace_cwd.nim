# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
# Nim port of fix_asar_workspace_cwd.py

import std/[os, strformat, strutils]
import regex

proc apply*(input: string): string =
  var content = input

  # Idempotency check
  if content.contains("__cdb_sanitizeCwd"):
    echo "  [SKIP] Already patched (__cdb_sanitizeCwd found)"
    return content

  let original = content
  var patchesApplied = 0

  # 1. Inject helper function after "use strict";
  const SANITIZE_FN = "var __cdb_sanitizeCwd=function(p){if(process.platform===\"linux\"&&typeof p===\"string\"&&/app\\.asar/.test(p)){return require(\"os\").homedir()}return p};"

  const USE_STRICT = "\"use strict\";"
  let idx = content.find(USE_STRICT)
  if idx >= 0:
    let injectPoint = idx + USE_STRICT.len
    content = content[0 ..< injectPoint] & SANITIZE_FN & content[injectPoint .. ^1]
    echo "  [OK] Injected __cdb_sanitizeCwd helper (after 'use strict')"
  else:
    content = SANITIZE_FN & content
    echo "  [OK] Injected __cdb_sanitizeCwd helper (at file start)"

  # 2. checkTrust bridge
  let patCt = re2"(checkTrust\()([\w$]+)(\)\{)(return [\w$]+\.info\()"
  var cCt = 0
  content = content.replace(patCt, proc (m: RegexMatch2, s: string): string =
    if cCt >= 1: return s[m.boundaries]  # count=1 equivalent — but Nim regex doesn't have count limit
    inc cCt
    let g1 = s[m.group(0)]
    let arg = s[m.group(1)]
    let g3 = s[m.group(2)]
    let g4 = s[m.group(3)]
    g1 & arg & g3 & arg & "=__cdb_sanitizeCwd(" & arg & ");" & g4
  )
  if cCt > 0:
    patchesApplied += cCt
    echo &"  [OK] checkTrust bridge: {cCt} match(es)"
  else:
    echo "  [WARN] checkTrust bridge: 0 matches"

  # 3. saveTrust bridge
  let patSt = re2"(async saveTrust\()([\w$]+)(\)\{)([\w$]+\.info\()"
  var cSt = 0
  content = content.replace(patSt, proc (m: RegexMatch2, s: string): string =
    if cSt >= 1: return s[m.boundaries]
    inc cSt
    let g1 = s[m.group(0)]
    let arg = s[m.group(1)]
    let g3 = s[m.group(2)]
    let g4 = s[m.group(3)]
    g1 & arg & g3 & arg & "=__cdb_sanitizeCwd(" & arg & ");" & g4
  )
  if cSt > 0:
    patchesApplied += cSt
    echo &"  [OK] saveTrust bridge: {cSt} match(es)"
  else:
    echo "  [WARN] saveTrust bridge: 0 matches"

  # 4. start bridge
  let patStart = re2"""(async start\()([\w$]+)(\)\{)(return [\w$]+\.info\("LocalSessions\.start:"\))"""
  var cStart = 0
  content = content.replace(patStart, proc (m: RegexMatch2, s: string): string =
    if cStart >= 1: return s[m.boundaries]
    inc cStart
    let g1 = s[m.group(0)]
    let arg = s[m.group(1)]
    let g3 = s[m.group(2)]
    let g4 = s[m.group(3)]
    g1 & arg & g3 & arg & ".cwd=__cdb_sanitizeCwd(" & arg & ".cwd);" & g4
  )
  if cStart > 0:
    patchesApplied += cStart
    echo &"  [OK] start bridge: {cStart} match(es)"
  else:
    echo "  [WARN] start bridge: 0 matches"

  # 5. startCodeSession (handler with conditional)
  let patScs = re2"(startCodeSession:[\w$]+\?async\()([\w$]+)(,[\w$]+,[\w$]+,[\w$]+\)=>\{)"
  var cScs = 0
  content = content.replace(patScs, proc (m: RegexMatch2, s: string): string =
    inc cScs
    let g1 = s[m.group(0)]
    let arg = s[m.group(1)]
    let g3 = s[m.group(2)]
    g1 & arg & g3 & arg & "=__cdb_sanitizeCwd(" & arg & ");"
  )
  if cScs > 0:
    patchesApplied += cScs
    echo &"  [OK] startCodeSession bridges: {cScs} match(es)"
  else:
    echo "  [WARN] startCodeSession bridges: 0 matches"

  # dispatch startCodeSession (without conditional)
  let patScs2 = re2"(startCodeSession:async\()([\w$]+)(,[\w$]+,[\w$]+,[\w$]+\)=>\{)"
  var cScs2 = 0
  content = content.replace(patScs2, proc (m: RegexMatch2, s: string): string =
    inc cScs2
    let g1 = s[m.group(0)]
    let arg = s[m.group(1)]
    let g3 = s[m.group(2)]
    g1 & arg & g3 & arg & "=__cdb_sanitizeCwd(" & arg & ");"
  )
  if cScs2 > 0:
    patchesApplied += cScs2
    echo &"  [OK] dispatch startCodeSession: {cScs2} match(es)"
  else:
    echo "  [WARN] dispatch startCodeSession: 0 matches"

  const EXPECTED = 5
  if patchesApplied < EXPECTED:
    echo &"  [FAIL] Only {patchesApplied}/{EXPECTED} patches applied — check [WARN]/[FAIL] messages above"
    raise newException(ValueError, &"fix_asar_workspace_cwd: only {patchesApplied}/{EXPECTED} applied")

  if content == original:
    echo &"  [OK] All {patchesApplied} patches already applied (no changes needed)"
    return original

  result = content

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_asar_workspace_cwd <file>"
    quit(1)
  let file = paramStr(1)
  echo "=== Patch: fix_asar_workspace_cwd ==="
  echo &"  Target: {file}"
  let input = readFile(file)
  let output = apply(input)
  if output != input:
    writeFile(file, output)
    echo &"  [PASS] Patches applied"
  else:
    echo "  [OK] No changes needed"
