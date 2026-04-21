# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
#
# Nim port of fix_cowork_linux.py — produces byte-identical output.
#
# The MODE_PREAMBLE_JS snippet lives in js/cowork_mode_preamble.js and is
# shared verbatim between the Python and Nim implementations. This Nim
# source embeds it at compile time via staticRead; the Python source reads
# it at runtime. No codegen; the .js file is the single source of truth.
#
# 11 sub-patches:
#   0  mode preamble at "use strict"; start
#   A  VM client loader (extends Li check to include Linux)
#   B  socket path (mode-selected Unix socket)
#   C1 bundle config (inject linux:{x64:[]})
#   C2 bundle lookup alias (runtime-gated linux→win32)
#   D  pathToClaudeCodeExecutable (dynamic on Linux)
#   E  error detection (extend /usr/local/bin/claude check)
#   F  present_files (allow host outputs dir)
#   G-mount  vmProcessId guard removal
#   G-delete vmProcessId guard removal
#   H  smol-bin copy gate (runtime-gated on kvm mode)
#
# Patches always run on clean bundles — no "already patched" fast path.

import std/[os, strformat, strutils, options]
import std/nre

const MODE_PREAMBLE_JS = staticRead("../js/cowork_mode_preamble.js")

proc replaceFirst(content: var string, pattern: Regex,
                  subFn: proc(m: RegexMatch): string): int =
  let maybe = content.find(pattern)
  if maybe.isNone: return 0
  let m = maybe.get()
  let bounds = m.matchBounds
  content = content[0 ..< bounds.a] & subFn(m) & content[bounds.b + 1 .. ^1]
  return 1

proc replaceAllRegex(content: var string, pattern: Regex,
                     subFn: proc(m: RegexMatch): string): int =
  var count = 0
  content = content.replace(pattern, proc(m: RegexMatch): string =
    inc count
    subFn(m)
  )
  return count

proc apply*(input: string): string =
  var content = input
  let original = input
  var patchesApplied = 0
  const EXPECTED_PATCHES = 11

  # ── Patch 0: Mode preamble at file start (right after "use strict";) ──
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

  # ── Patch A: VM client loader — extend Li check to include Linux ──
  block:
    let pat = re"""([\w$]+)\?([\w$]+)=(\{vm:[\w$]+\}):\2=\(await import\("@ant/claude-swift"\)\)\.default"""
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

  # ── Patch B: Socket path — mode-aware Unix socket on Linux ──
  block:
    # The original bytes pattern in Python is
    #   b'"\\\\\\\\.\\\\pipe\\\\cowork-vm-service"'
    # which decodes to the literal JS source bytes:
    #   "\\\\.\\pipe\\cowork-vm-service"
    # i.e. 8 backslashes encoding the Windows pipe path.
    const pipePath = "\"\\\\\\\\.\\\\pipe\\\\cowork-vm-service\""
    const pipeSearch = "=" & pipePath

    let idx = content.find(pipeSearch)
    if idx != -1:
      # Walk backwards to find start of variable name
      var start = idx - 1
      while start >= 0:
        let c = content[start]
        if c.isAlphaNumeric or c == '_' or c == '$':
          dec start
        else:
          break
      inc start
      let varName = content[start ..< idx]

      let replacement =
        varName &
        "=process.platform===\"linux\"?" &
        "(process.env.XDG_RUNTIME_DIR||\"/tmp\")+(globalThis.__coworkKvmMode?\"/cowork-kvm-service.sock\":\"/cowork-vm-service.sock\")" &
        ":" & pipePath

      content = content[0 ..< start] & replacement & content[idx + pipeSearch.len .. ^1]
      echo &"  [OK] B socket path: runtime-selected Unix socket on Linux (var={varName})"
      inc patchesApplied
    else:
      echo "  [FAIL] B socket path: pipe path not found"

  # ── Patch C1: Inject ",linux:{x64:[]}" into bundle files config ──
  block:
    const win32Marker = "win32:{"
    let win32Idx = content.find(win32Marker)
    if win32Idx >= 0:
      const x64Marker = ",x64:["
      let x64Idx = content.find(x64Marker, win32Idx)
      if x64Idx >= 0:
        # Position of the opening '['
        let arrayStart = x64Idx + x64Marker.len - 1
        var depth = 0
        var pos = arrayStart
        var matched = false
        while pos < content.len:
          let ch = content[pos]
          if ch == '[':
            inc depth
          elif ch == ']':
            dec depth
            if depth == 0:
              matched = true
              break
          inc pos
        if matched:
          let afterArray = pos + 1
          if afterArray < content.len and content[afterArray] == '}':
            const inject = ",linux:{x64:[]}"
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

  # ── Patch C2: Alias linux→win32 at Xs.files[…] lookup sites ──
  block:
    let pat = re"""(const ([\w$]+)=)process\.platform(,[\w$]+=[\w$]+\(\);return [\w$]+\.files\[\2\])"""
    let n = replaceAllRegex(content, pat, proc(m: RegexMatch): string =
      m.captures[0] &
        "(globalThis.__coworkKvmMode?(process.platform===\"linux\"?\"win32\":process.platform):process.platform)" &
        m.captures[2]
    )
    if n >= 1:
      echo &"  [OK] C2 bundle lookup alias: linux→win32 when kvm mode ({n} site(s))"
      inc patchesApplied
    else:
      echo "  [FAIL] C2 bundle lookup alias: no matching sites found"

  # ── Patch D: pathToClaudeCodeExecutable — dynamic on Linux ──
  block:
    const claudePathOld = "pathToClaudeCodeExecutable:\"/usr/local/bin/claude\""
    const claudePathNew =
      "pathToClaudeCodeExecutable:" &
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
    if idx != -1:
      content = content[0 ..< idx] & claudePathNew & content[idx + claudePathOld.len .. ^1]
      echo "  [OK] D Claude Code path: dynamic resolution on Linux"
      inc patchesApplied
    else:
      echo "  [FAIL] D Claude Code path: pattern not found"

  # ── Patch E: Error detection — extend Linux paths ──
  block:
    let pat = re"""([\w$]+)(\.includes\("/usr/local/bin/claude"\))"""
    let n = replaceFirst(content, pat, proc(m: RegexMatch): string =
      let v = m.captures[0]
      "(" & v & ".includes(\"/usr/local/bin/claude\")||" & v & ".includes(\"/usr/bin/claude\")||" & v & ".includes(\"/.local/bin/claude\"))"
    )
    if n >= 1:
      echo "  [OK] E error detection: extended for Linux paths"
      inc patchesApplied
    else:
      echo "  [FAIL] E error detection: pattern not found"

  # ── Patch F: present_files — allow host outputs dir paths ──
  block:
    let pat = re"""for\(const\{file_path:([\w$]+),vmPath:([\w$]+)\}of ([\w$]+)\)\{if\(([\w$]+)\(\2,([\w$]+)\.vmProcessName\)\)continue;\(([\w$]+)\?([\w$]+)\(\2,\6\):null\)===null&&([\w$]+)\.push\(\1\)\}"""
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
        "if(_ho&&(" & fVar & "===_ho||" & fVar & ".startsWith(_ho+\"/\")))return;" & uVar & ".push(" & fVar & ")})()}"
    )
    if n >= 1:
      echo &"  [OK] F present_files: host outputs dir allowed ({n} match)"
      inc patchesApplied
    else:
      echo "  [FAIL] F present_files: pattern not found"

  # ── Patch G-mount: remove mountFolderForSession vmProcessId guard ──
  block:
    let pat = re"""if\s*\(\s*!\s*[a-zA-Z_$][\w$]*\s*\|\|\s*!\s*[a-zA-Z_$][\w$]*\s*\)\s*return\s*\{\s*ok\s*:\s*!\s*1\s*,\s*error\s*:\s*"Session VM process not available\. The session may not be fully initialized\."\s*\}\s*;?"""
    let n = replaceAllRegex(content, pat, proc(m: RegexMatch): string = "")
    if n >= 1:
      echo &"  [OK] G-mount vmProcessId guard: removed ({n} match)"
      inc patchesApplied
    else:
      echo "  [FAIL] G-mount vmProcessId guard: pattern not found"

  # ── Patch G-delete: remove delete-permission vmProcessId guard ──
  block:
    let pat = re"""if\s*\(\s*!\s*[a-zA-Z_$][\w$]*\s*\)\s*return\s*\{\s*content\s*:\s*\[\s*\{\s*type\s*:\s*"text"\s*,\s*text\s*:\s*"Session VM process not available\. The session may not be fully initialized\."\s*\}\s*\]\s*,\s*isError\s*:\s*!\s*0\s*\}\s*;?"""
    let n = replaceAllRegex(content, pat, proc(m: RegexMatch): string = "")
    if n >= 1:
      echo &"  [OK] G-delete vmProcessId guard: removed ({n} match)"
      inc patchesApplied
    else:
      echo "  [FAIL] G-delete vmProcessId guard: pattern not found"

  # ── Patch H: smol-bin copy gate — runtime-gated on kvm mode ──
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

  # ── Checks ────────────────────────────────────────────────────
  if patchesApplied < EXPECTED_PATCHES:
    raise newException(ValueError,
      &"Only {patchesApplied}/{EXPECTED_PATCHES} patches applied — check [WARN]/[FAIL] messages above")

  echo &"  [PASS] {patchesApplied} patches applied"
  result = content
  discard original

when isMainModule:
  let file = paramStr(1)
  echo "=== Patch: fix_cowork_linux ==="
  echo &"  Target: {file}"
  let input = readFile(file)
  let output = apply(input)
  if output != input:
    writeFile(file, output)
