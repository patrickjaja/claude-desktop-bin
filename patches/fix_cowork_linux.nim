# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
#
# Enable Cowork VM features on Linux with native/KVM runtime switch.
#
# The MODE_PREAMBLE_JS snippet lives in js/cowork_mode_preamble.js and is
# embedded at compile time via staticRead. It sets globalThis.__coworkKvmMode
# at runtime, allowing the same patched bundle to work in both native and
# KVM modes.
#
# Eleven sub-patches:
#   0       Mode preamble at "use strict"; start
#   A       VM client loader (extends Li check to include Linux)
#   B       Socket path (mode-selected Unix socket)
#   C1      Bundle config (inject linux:{x64:[]})
#   C2      Bundle lookup alias (runtime-gated linux->win32)
#   D       pathToClaudeCodeExecutable (dynamic on Linux)
#   E       Error detection (extend /usr/local/bin/claude check)
#   F       present_files (allow host outputs dir)
#   G-mount   vmProcessId guard removal (mountFolderForSession)
#   G-delete  vmProcessId guard removal (delete permission)
#   H       smol-bin copy gate (runtime-gated on kvm mode)
#
# Patches always run on clean bundles — no "already patched" fast path.

import std/[os, strformat, strutils, options]
import std/nre

const MODE_PREAMBLE_JS = staticRead("../js/cowork_mode_preamble.js")
const EXPECTED_PATCHES = 11

proc replaceFirst(content: var string, pattern: Regex,
                  subFn: proc(m: RegexMatch): string): int =
  ## Replace only the first match of `pattern` in `content`.
  let maybe = content.find(pattern)
  if maybe.isNone: return 0
  let m = maybe.get()
  let bounds = m.matchBounds
  content = content[0 ..< bounds.a] & subFn(m) & content[bounds.b + 1 .. ^1]
  return 1

proc replaceAllRegex(content: var string, pattern: Regex,
                     subFn: proc(m: RegexMatch): string): int =
  ## Replace all matches of `pattern` in `content`.
  var count = 0
  content = content.replace(pattern, proc(m: RegexMatch): string =
    inc count
    subFn(m)
  )
  return count

proc apply*(input: string): string =
  var content = input
  var patchesApplied = 0

  # -- Patch 0: Mode preamble at file start (right after "use strict";) --
  block:
    const strictMarker = "\"use strict\";"
    let strictIdx = content.find(strictMarker)
    if strictIdx == 0:
      let insertionPoint = strictMarker.len
      content = content[0 ..< insertionPoint] & MODE_PREAMBLE_JS & content[insertionPoint .. ^1]
      echo "  [OK] 0 mode preamble: injected after \"use strict\""
      inc patchesApplied
    else:
      echo "  [FAIL] 0 mode preamble: \"use strict\"; not at file start"

  # -- Patch A: Extend TypeScript VM client to Linux --
  # Uses backreference: \2 ensures same variable in both branches
  block:
    let pat = re"([\w$]+)\?([\w$]+)=(\{vm:[\w$]+\}):\2=\(await import\(""@ant/claude-swift""\)\)\.default"
    let n = replaceAllRegex(content, pat, proc(m: RegexMatch): string =
      let liVar = m.captures[0]
      let efVar = m.captures[1]
      let vmObj = m.captures[2]
      "(" & liVar & "||process.platform===\"linux\")?" & efVar & "=" & vmObj & ":" & efVar & "=(await import(\"@ant/claude-swift\")).default"
    )
    if n >= 1:
      echo &"  [OK] A VM client loader: extended to Linux ({n} match)"
      inc patchesApplied
    else:
      echo "  [FAIL] A VM client loader: 0 matches"

  # -- Patch B: Socket path — mode-aware Unix socket on Linux --
  block:
    let pipePath = "\"\\\\\\\\.\\\\pipe\\\\cowork-vm-service\""
    let pipeSearch = "=" & pipePath

    let idx = content.find(pipeSearch)
    if idx >= 0:
      # Walk backwards to find start of variable name
      var start = idx - 1
      while start >= 0 and (content[start].isAlphaNumeric() or content[start] == '_' or content[start] == '$'):
        dec start
      inc start
      let varName = content[start ..< idx]
      let replacement = varName &
        "=process.platform===\"linux\"?" &
        "(process.env.XDG_RUNTIME_DIR||\"/tmp\")+(globalThis.__coworkKvmMode?\"/cowork-kvm-service.sock\":\"/cowork-vm-service.sock\")" &
        ":" & pipePath
      content = content[0 ..< start] & replacement & content[idx + pipeSearch.len .. ^1]
      echo &"  [OK] B socket path: runtime-selected Unix socket on Linux (var={varName})"
      inc patchesApplied
    else:
      echo "  [FAIL] B socket path: pipe path not found"

  # -- Patch C1: Add Linux to _i.files bundle config with EMPTY file list --
  block:
    let win32Marker = "win32:{"
    let win32Idx = content.find(win32Marker)
    if win32Idx >= 0:
      let x64Marker = ",x64:["
      let x64Idx = content.find(x64Marker, win32Idx)
      if x64Idx >= 0:
        # Skip past the x64 array (balanced bracket matching)
        let arrayStart = x64Idx + x64Marker.len - 1  # Position of '['
        var depth = 0
        var pos = arrayStart
        var matched = false
        while pos < content.len:
          if content[pos] == '[':
            inc depth
          elif content[pos] == ']':
            dec depth
            if depth == 0:
              matched = true
              break
          inc pos

        if matched:
          # After x64 array ends at pos+1, expect } (close win32)
          let afterArray = pos + 1
          if afterArray < content.len and content[afterArray] == '}':
            let inject = ",linux:{x64:[]}"
            content = content[0 .. afterArray] & inject & content[afterArray + 1 .. ^1]
            echo "  [OK] C1 bundle config: linux platform added (empty file list)"
            inc patchesApplied
          else:
            echo "  [FAIL] C1 bundle config: unexpected structure after x64 array"
        else:
          echo "  [FAIL] C1 bundle config: x64 array not balanced"
      else:
        echo "  [FAIL] C1 bundle config: x64 array not found in win32 block"
    else:
      echo "  [FAIL] C1 bundle config: win32 block not found"

  # -- Patch C2: Alias linux->win32 at Xs.files[...] lookup sites --
  block:
    let pat = re"""(const ([\w$]+)=)process\.platform(,[\w$]+=[\w$]+\(\);return [\w$]+\.files\[\2\])"""
    let n = replaceAllRegex(content, pat, proc(m: RegexMatch): string =
      m.captures[0] &
        "(globalThis.__coworkKvmMode?(process.platform===\"linux\"?\"win32\":process.platform):process.platform)" &
        m.captures[2]
    )
    if n >= 1:
      echo &"  [OK] C2 bundle lookup alias: linux->win32 when kvm mode ({n} site(s))"
      inc patchesApplied
    else:
      echo "  [FAIL] C2 bundle lookup alias: no matching sites found"

  # -- Patch D: Fix pathToClaudeCodeExecutable for Linux --
  block:
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

    let idx = content.find(claudePathOld)
    if idx >= 0:
      content = content[0 ..< idx] & claudePathNew & content[idx + claudePathOld.len .. ^1]
      echo "  [OK] D Claude Code path: dynamic resolution on Linux"
      inc patchesApplied
    else:
      echo "  [FAIL] D Claude Code path: pattern not found"

  # -- Patch E: Extend error detection to recognize Linux paths --
  block:
    let pat = re"""([\w$]+)(\.includes\("/usr/local/bin/claude"\))"""
    let n = replaceFirst(content, pat, proc(m: RegexMatch): string =
      let v = m.captures[0]
      "(" & v & ".includes(\"/usr/local/bin/claude\")||" &
        v & ".includes(\"/usr/bin/claude\")||" &
        v & ".includes(\"/.local/bin/claude\"))"
    )
    if n >= 1:
      echo "  [OK] E error detection: extended for Linux paths"
      inc patchesApplied
    else:
      echo "  [FAIL] E error detection: pattern not found"

  # -- Patch F: Fix present_files to accept native host paths on Linux --
  block:
    let pat = re(
      r"for\(const\{file_path:([\w$]+),vmPath:([\w$]+)\}of ([\w$]+)\)\{" &
      r"if\(([\w$]+)\(\2,([\w$]+)\.vmProcessName\)\)continue;" &
      r"\(([\w$]+)\?([\w$]+)\(\2,\6\):null\)===null&&([\w$]+)\.push\(\1\)\}"
    )
    let n = replaceAllRegex(content, pat, proc(m: RegexMatch): string =
      let fVar = m.captures[0]
      let pVar = m.captures[1]
      let lVar = m.captures[2]
      let scratchpadFn = m.captures[3]
      let tVar = m.captures[4]
      let cVar = m.captures[5]
      let resolveFn = m.captures[6]
      let uVar = m.captures[7]
      "for(const{file_path:" & fVar & ",vmPath:" & pVar & "}of " & lVar & "){" &
        "if(" & scratchpadFn & "(" & pVar & "," & tVar & ".vmProcessName))continue;" &
        "(" & cVar & "?" & resolveFn & "(" & pVar & "," & cVar & "):null)===null&&" &
        "(()=>{const _ho=" & tVar & ".getHostOutputsDir();" &
        "if(_ho&&(" & fVar & "===_ho||" & fVar & ".startsWith(_ho+\"/\")))return;" &
        uVar & ".push(" & fVar & ")})()}"
    )
    if n >= 1:
      echo &"  [OK] F present_files: host outputs dir allowed ({n} match)"
      inc patchesApplied
    else:
      echo "  [FAIL] F present_files: pattern not found"

  # -- Patch G-mount: Remove mountFolderForSession vmProcessId guard --
  block:
    let pat = re"""if\s*\(\s*!\s*[a-zA-Z_$][\w$]*\s*\|\|\s*!\s*[a-zA-Z_$][\w$]*\s*\)\s*return\s*\{\s*ok\s*:\s*!\s*1\s*,\s*error\s*:\s*"Session VM process not available\. The session may not be fully initialized\."\s*\}\s*;?"""
    let n = replaceAllRegex(content, pat, proc(m: RegexMatch): string = "")
    if n >= 1:
      echo &"  [OK] G-mount vmProcessId guard: removed ({n} match)"
      inc patchesApplied
    else:
      echo "  [FAIL] G-mount vmProcessId guard: pattern not found"

  # -- Patch G-delete: Remove delete-permission vmProcessId guard --
  block:
    let pat = re"""if\s*\(\s*!\s*[a-zA-Z_$][\w$]*\s*\)\s*return\s*\{\s*content\s*:\s*\[\s*\{\s*type\s*:\s*"text"\s*,\s*text\s*:\s*"Session VM process not available\. The session may not be fully initialized\."\s*\}\s*\]\s*,\s*isError\s*:\s*!\s*0\s*\}\s*;?"""
    let n = replaceAllRegex(content, pat, proc(m: RegexMatch): string = "")
    if n >= 1:
      echo &"  [OK] G-delete vmProcessId guard: removed ({n} match)"
      inc patchesApplied
    else:
      echo "  [FAIL] G-delete vmProcessId guard: pattern not found"

  # -- Patch H: smol-bin copy gate — runtime-gated on kvm mode --
  block:
    let pat = re"""if\(process\.platform==="win32"\)(\{const [\w$]+=[\w$]+\(\),[\w$]+=[\w$]+\.join\(process\.resourcesPath,`smol-bin\.)"""
    let n = replaceAllRegex(content, pat, proc(m: RegexMatch): string =
      "if(process.platform===\"win32\"||process.platform===\"linux\"&&globalThis.__coworkKvmMode)" & m.captures[0]
    )
    if n >= 1:
      echo &"  [OK] H smol-bin copy gate: kvm-mode Linux opt-in ({n} match)"
      inc patchesApplied
    else:
      echo "  [FAIL] H smol-bin copy gate: win32 gate pattern not found"

  # -- Check results --
  if patchesApplied < EXPECTED_PATCHES:
    raise newException(ValueError,
      &"Only {patchesApplied}/{EXPECTED_PATCHES} patches applied -- check [WARN]/[FAIL] messages above")

  # Verify brace balance
  if content != input:
    let originalDelta = input.count('{') - input.count('}')
    let patchedDelta = content.count('{') - content.count('}')
    if originalDelta != patchedDelta:
      let diff = patchedDelta - originalDelta
      raise newException(ValueError,
        &"Patch introduced brace imbalance: {diff:+d} unmatched braces")

  result = content

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

  if output != input:
    writeFile(filePath, output)
    echo &"  [PASS] {EXPECTED_PATCHES} patches applied"
  else:
    echo &"  [OK] All {EXPECTED_PATCHES} patches already applied (no changes needed)"
