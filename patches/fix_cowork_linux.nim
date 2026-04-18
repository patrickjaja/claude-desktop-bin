# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
#
# Enable Cowork VM features on Linux.
#
# Six-part patch:
# A. Extend the TypeScript VM client to load on Linux, not just Windows.
# B. Replace Windows Named Pipe path with a Unix domain socket on Linux.
# C. Add Linux to _i.files bundle config with an empty file list.
# D. Fix pathToClaudeCodeExecutable for Linux (dynamic resolution).
# E. Extend error detection to recognize Linux paths.
# F. Fix present_files to accept native host paths on Linux.

import std/[os, strformat, strutils]
import std/nre

const EXPECTED_PATCHES = 6

proc apply*(input: string): string =
  result = input
  var patchesApplied = 0

  # -- Patch A: Extend TypeScript VM client to Linux --
  # Uses backreference: \2 ensures same variable in both branches
  let vmClientPattern = re"([\w$]+)\?([\w$]+)=(\{vm:[\w$]+\}):\2=\(await import\(""@ant/claude-swift""\)\)\.default"

  var countA = 0
  let newResult = result.replace(vmClientPattern, proc(m: RegexMatch): string =
    inc countA
    let liVar = m.captures[0]    # Li
    let efVar = m.captures[1]    # ef
    let vmObj = m.captures[2]    # {vm:vZe}
    "(" & liVar & "||process.platform===\"linux\")?" & efVar & "=" & vmObj & ":" & efVar & "=(await import(\"@ant/claude-swift\")).default"
  )
  if countA >= 1:
    result = newResult
    echo &"  [OK] VM client loader: extended to Linux ({countA} match)"
    inc patchesApplied
  else:
    echo "  [FAIL] VM client loader: 0 matches"

  # -- Patch B: Socket path for Linux --
  # Uses literal bytes search (no regex) to avoid backslash escaping hell
  let pipePath = "\"\\\\\\\\.\\\\pipe\\\\cowork-vm-service\""
  let pipeSearch = "=" & pipePath

  let pipeIdx = result.find(pipeSearch)
  if pipeIdx >= 0:
    # Walk backwards to find start of variable name
    var start = pipeIdx - 1
    while start >= 0 and (result[start].isAlphaNumeric() or result[start] == '_' or result[start] == '$'):
      dec start
    inc start
    let varName = result[start ..< pipeIdx]
    let replacement = varName & "=process.platform===\"linux\"?(process.env.XDG_RUNTIME_DIR||\"/tmp\")+\"/cowork-vm-service.sock\":" & pipePath
    result = result[0 ..< start] & replacement & result[pipeIdx + pipeSearch.len .. ^1]
    echo &"  [OK] Socket path: Unix socket on Linux (var={varName})"
    inc patchesApplied
  else:
    echo "  [WARN] Socket path: pipe path not found"

  # -- Patch C: Add Linux to _i.files bundle config with EMPTY file list --
  let win32Marker = "win32:{"
  let win32Idx = result.find(win32Marker)
  if win32Idx >= 0:
    let x64Marker = ",x64:["
    let x64Idx = result.find(x64Marker, win32Idx)
    if x64Idx >= 0:
      # Skip past the x64 array (balanced bracket matching)
      let arrayStart = x64Idx + x64Marker.len - 1  # Position of '['
      var depth = 0
      var pos = arrayStart
      while pos < result.len:
        if result[pos] == '[':
          inc depth
        elif result[pos] == ']':
          dec depth
          if depth == 0:
            break
        inc pos

      # After x64 array ends at pos+1, expect } (close win32)
      let afterArray = pos + 1
      if afterArray < result.len and result[afterArray] == '}':
        let inject = ",linux:{x64:[]}"
        result = result[0 ..< afterArray + 1] & inject & result[afterArray + 1 .. ^1]
        echo "  [OK] Bundle config: Linux platform added (empty file list -- no VM download)"
        inc patchesApplied
      else:
        echo "  [WARN] Bundle config: unexpected structure after x64 array"
    else:
      echo "  [WARN] Bundle config: x64 array not found in win32 block"
  else:
    echo "  [WARN] Bundle config: win32 block not found"

  # -- Patch D: Fix pathToClaudeCodeExecutable for Linux --
  let claudePathOld = "pathToClaudeCodeExecutable:\"/usr/local/bin/claude\""
  let claudePathNew = "pathToClaudeCodeExecutable:" &
    "(()=>{if(process.platform!==\"linux\")return\"/usr/local/bin/claude\";" &
    "const fs=require(\"fs\");" &
    "for(const p of[\"/usr/bin/claude\"," &
    "(process.env.HOME||\"\")+\"/.local/bin/claude\"," &
    "\"/usr/local/bin/claude\"])" &
    "if(fs.existsSync(p))return p;" &
    "try{return require(\"child_process\").execSync(\"which claude\",{encoding:\"utf-8\"}).trim()}" &
    "catch(e){}" &
    "return\"claude\"})()"

  if claudePathOld in result:
    result = result.replace(claudePathOld, claudePathNew)
    echo "  [OK] Claude Code path: dynamic resolution on Linux"
    inc patchesApplied
  else:
    echo "  [WARN] Claude Code path: pattern not found"

  # -- Patch E: Extend error detection to recognize Linux paths --
  let errorDetectPattern = re"([\w$]+)(\.includes\(""/usr/local/bin/claude""\))"

  var errorCount = 0
  let errorResult = result.replace(errorDetectPattern, proc(m: RegexMatch): string =
    inc errorCount
    if errorCount > 1:
      return m.match  # only replace first
    let varName = m.captures[0]
    "(" & varName & ".includes(\"/usr/local/bin/claude\")||" &
      varName & ".includes(\"/usr/bin/claude\")||" &
      varName & ".includes(\"/.local/bin/claude\"))"
  )
  if errorCount >= 1:
    result = errorResult
    echo "  [OK] Error detection: extended for Linux paths"
    inc patchesApplied
  else:
    echo "  [WARN] Error detection: pattern not found"

  # -- Patch F: Fix present_files to accept native host paths on Linux --
  let alreadyF = ".getHostOutputsDir();if(_ho&&(" in result
  if alreadyF:
    echo "  [OK] F present_files native paths: already patched (skipped)"
    inc patchesApplied
  else:
    let presentFilesPattern = re(
      r"for\(const\{file_path:([\w$]+),vmPath:([\w$]+)\}of ([\w$]+)\)\{" &
      r"if\(([\w$]+)\(\2,([\w$]+)\.vmProcessName\)\)continue;" &
      r"\(([\w$]+)\?([\w$]+)\(\2,\6\):null\)===null&&([\w$]+)\.push\(\1\)\}"
    )
    let pfMatch = result.find(presentFilesPattern)
    if pfMatch.isSome:
      let m = pfMatch.get()
      let fVar = m.captures[0]
      let pVar = m.captures[1]
      let lVar = m.captures[2]
      let scratchpadFn = m.captures[3]
      let tVar = m.captures[4]
      let cVar = m.captures[5]
      let resolveFn = m.captures[6]
      let uVar = m.captures[7]
      let replacement =
        "for(const{file_path:" & fVar & ",vmPath:" & pVar & "}of " & lVar & "){" &
        "if(" & scratchpadFn & "(" & pVar & "," & tVar & ".vmProcessName))continue;" &
        "(" & cVar & "?" & resolveFn & "(" & pVar & "," & cVar & "):null)===null&&" &
        "(()=>{const _ho=" & tVar & ".getHostOutputsDir();" &
        "if(_ho&&(" & fVar & "===_ho||" & fVar & ".startsWith(_ho+\"/\")))return;" &
        uVar & ".push(" & fVar & ")})()}"
      let bounds = m.matchBounds
      result = result[0 ..< bounds.a] & replacement & result[bounds.b + 1 .. ^1]
      echo &"  [OK] F present_files native paths: host outputs dir allowed (1 match)"
      inc patchesApplied
    else:
      echo "  [FAIL] F present_files native paths: pattern not found"

  # -- Check results --
  if patchesApplied < EXPECTED_PATCHES:
    echo &"  [FAIL] Only {patchesApplied}/{EXPECTED_PATCHES} patches applied -- check [WARN]/[FAIL] messages above"
    quit(1)

  # Verify brace balance
  if result != input:
    let originalDelta = input.count('{') - input.count('}')
    let patchedDelta = result.count('{') - result.count('}')
    if originalDelta != patchedDelta:
      let diff = patchedDelta - originalDelta
      echo &"  [FAIL] Patch introduced brace imbalance: {diff:+d} unmatched braces"
      quit(1)

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_cowork_linux <path_to_index.js>"
    quit(1)

  let filePath = paramStr(1)
  echo "=== Patch: fix_cowork_linux ==="
  echo "  Target: " & filePath

  if not fileExists(filePath):
    echo "  [FAIL] File not found: " & filePath
    quit(1)

  let input = readFile(filePath)
  let output = apply(input)

  if output == input:
    echo &"  [OK] All {EXPECTED_PATCHES} patches already applied (no changes needed)"
  else:
    writeFile(filePath, output)
    echo &"  [PASS] {EXPECTED_PATCHES} patches applied"
