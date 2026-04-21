# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
#
# Make computer-use work on Linux by removing platform gates and providing
# a Linux executor.  Supports two backends:
#   - Regular cross-distro executor (X11/Wayland via xdotool/ydotool/grim/…)
#   - kwin-portal-bridge executor (KDE Plasma via org.kde.KWin portal)
#
# 35 sub-patches covering:
#   1  Linux executor injection at app.on("ready") — both regular + kwin-wayland
#   2  ese Set: add "linux"
#   4  createDarwinExecutor: Linux fallback
#   4b cu lock acquire: start bridge session
#   4b.2 cu lock release: stop bridge session
#   5  ensureOsPermissions: skip TCC on Linux
#   5b screenshot intro note workaround
#   6  handleToolCall: hybrid dispatch (gated: regular-only; kwin falls through)
#   7  teach overlay controller: verify CU gate
#   7b teach overlay controller: bridge-backed init (kwin-wayland)
#   7c cu side-panel: bridge-backed init (kwin-wayland)
#   8  teach overlay mouse: tooltip-bounds polling
#   8a cu glow overlay: disabled in kwin-wayland mode
#   9a teach overlay: neutralize setIgnoreMouseEvents in yJt
#   9b teach overlay: neutralize setIgnoreMouseEvents in SUn
#  10  teach overlay: VM-aware transparency
#  10b teach overlay display: force primary monitor
#  11  mVt isEnabled: force true on Linux
#  12  rj chicagoEnabled bypass: force true on Linux
#  13a-13g: Tool description patches (7 sub-patches)
#  13b.kwin-*: KDE-specific tool description patches (5 sub-patches)
#  14a-14d: System prompt patches (4 sub-patches, 14d = kwin KDE env prompt)

import std/[os, strformat, strutils, options]
import std/nre

# Extracted JS loaded via staticRead
const LINUX_EXECUTOR_JS = staticRead("../js/cu_linux_executor.js")
const LINUX_HANDLER_INJECTION_JS = staticRead("../js/cu_handler_injection.js")
const MODE_PREAMBLE_JS = staticRead("../js/cu_mode_preamble.js")
const KWIN_EXECUTOR_SOURCE = staticRead("../js/executor_linux.js")

const EXPECTED_PATCHES = 35

# ─── helpers ────────────────────────────────────────────────────────────────

proc replaceFirst(content: var string, pattern: Regex,
                  subFn: proc(m: RegexMatch): string): int =
  ## Replace the first regex match. Returns 1 if replaced, 0 otherwise.
  let maybeMatch = content.find(pattern)
  if maybeMatch.isNone: return 0
  let m = maybeMatch.get()
  let bounds = m.matchBounds
  content = content[0..<bounds.a] & subFn(m) & content[bounds.b + 1 .. ^1]
  return 1

proc replaceAllRegex(content: var string, pattern: Regex,
                     subFn: proc(m: RegexMatch): string): int =
  ## Replace ALL regex matches. Returns match count.
  var count = 0
  content = content.replace(pattern, proc(m: RegexMatch): string =
    inc count
    subFn(m)
  )
  return count

proc replaceLiteralFirst(content: var string, needle, sub: string): int =
  ## Replace first literal (non-regex) occurrence. Returns 1 if replaced, 0 otherwise.
  let idx = content.find(needle)
  if idx == -1: return 0
  content = content[0..<idx] & sub & content[idx + needle.len .. ^1]
  return 1

proc replaceLiteralAll(content: var string, needle, sub: string): int =
  ## Replace all literal occurrences. Returns match count.
  var idx = 0
  while true:
    let found = content.find(needle, idx)
    if found == -1: break
    content = content[0..<found] & sub & content[found + needle.len .. ^1]
    idx = found + sub.len
    inc result

proc countOccurrences(content, needle: string): int =
  var idx = 0
  while true:
    let found = content.find(needle, idx)
    if found == -1: break
    inc result
    idx = found + needle.len

proc findStringMarker(content: string, messages: varargs[string]): int =
  ## Find a string marker in either single or double quotes.
  for message in messages:
    for quote in ["\"", "'"]:
      let needle = quote & message & quote
      let idx = content.find(needle)
      if idx != -1: return idx
    let idx = content.find(message)
    if idx != -1: return idx
  return -1

type FunctionInfo = object
  headerEnd: int
  header: string
  body: string

proc findFunctionBeforeMarker(content: string, markerIndex: int): Option[FunctionInfo] =
  ## Find the enclosing function header before a marker index.
  let fnIdx = content.rfind("function ", last = markerIndex - 1)
  if fnIdx == -1: return none(FunctionInfo)
  let headerEnd = content.find('{', start = fnIdx, last = markerIndex - 1)
  if headerEnd == -1: return none(FunctionInfo)
  return some(FunctionInfo(
    headerEnd: headerEnd,
    header: content[fnIdx .. headerEnd],
    body: content[headerEnd + 1 ..< markerIndex],
  ))

# ─── kwin-wayland executor transformation ───────────────────────────────────

proc buildKwinLinuxExecutorInjection(): string =
  ## Transform ES-module imports to CommonJS requires, strip `export`
  ## keywords, wrap in an IIFE, and assign to globalThis.__linuxExecutor.
  var js = KWIN_EXECUTOR_SOURCE
  js = js.replace(
    "import { execFile as execFileCb, spawnSync } from 'node:child_process'\n",
    "var { execFile: execFileCb, spawnSync } = require(\"node:child_process\");\n",
  )
  js = js.replace(
    "import { execFile as execFileCb } from 'node:child_process'\n",
    "var { execFile: execFileCb } = require(\"node:child_process\");\n",
  )
  js = js.replace(
    "import { screen as electronScreen } from 'electron'\n",
    "var { screen: electronScreen } = require(\"electron\");\n",
  )
  js = js.replace(
    "import { promisify } from 'node:util'\n",
    "var { promisify } = require(\"node:util\");\n",
  )
  # Strip `export ` at the start of any line (multiline mode)
  js = js.replace(re"(?m)^export\s+", "")
  result = "(function(){\n" & js.strip(leading = false, trailing = true) &
    "\n\nglobalThis.__linuxExecutor = createLinuxExecutor({ hostBundleId: \"com.anthropic.claude-desktop\" });\n})();\n"

# ─── main patch ─────────────────────────────────────────────────────────────

proc apply*(input: string): string =
  var content = input
  var patchesApplied = 0
  var changes = 0

  # ── Patch 1: inject executors + mode preamble at app.on("ready") ───────
  block:
    let regularJs = LINUX_EXECUTOR_JS.strip()
    let kwinJs = buildKwinLinuxExecutorInjection().strip()
    let pat = re"""(app\.on\("ready",async\(\)=>\{)"""
    let n = replaceFirst(content, pat, proc(m: RegexMatch): string =
      m.captures[0] & "if(process.platform===\"linux\"){" & MODE_PREAMBLE_JS &
        "if(globalThis.__cuKwinMode){" & kwinJs & "}else{" & regularJs & "}}"
    )
    if n >= 1:
      echo &"  [OK] Linux executor: injected regular + kwin-wayland variants ({n} match)"
      inc changes, n
      inc patchesApplied
    else:
      echo "  [FAIL] app.on(\"ready\") pattern: 0 matches"
      quit(1)

  # ── Patch 2: add "linux" to the platform Set ───────────────────────────
  block:
    let needle = """new Set(["darwin","win32"])"""
    let repl = """new Set(["darwin","win32","linux"])"""
    let n = replaceLiteralFirst(content, needle, repl)
    if n >= 1:
      echo &"  [OK] ese Set: added linux ({n} match)"
      inc changes, n
      inc patchesApplied
    else:
      let already = content.count("""new Set(["darwin","win32","linux"])""")
      if already >= 1:
        echo &"  [OK] ese Set: linux already present in all {already} Set(s)"
        inc patchesApplied
      else:
        echo "  [FAIL] ese Set pattern: 0 matches"
        quit(1)

  # ── Patch 4: createDarwinExecutor Linux fallback ───────────────────────
  block:
    let pat = re"""(function [\w$]+\([\w$]+\)\{)if\(process\.platform!=="darwin"\)throw new Error"""
    let n = replaceFirst(content, pat, proc(m: RegexMatch): string =
      m.captures[0] &
        "if(process.platform===\"linux\"&&globalThis.__linuxExecutor)return globalThis.__linuxExecutor;" &
        "if(process.platform!==\"darwin\")throw new Error"
    )
    if n >= 1:
      echo &"  [OK] createDarwinExecutor: Linux fallback ({n} match)"
      inc changes, n
      inc patchesApplied
    else:
      echo "  [FAIL] createDarwinExecutor pattern: 0 matches"
      quit(1)

  # ── Patch 4b (kwin-wayland): cu lock acquire → __setLockHeld(true) ──────
  block:
    let pat = re"""this\.holder===void 0&&\(this\.holder=([\w$]+),this\.emit\("cuLockChanged",\{holder:\1\}\),([\w$]+)\(\)\)"""
    let n = replaceFirst(content, pat, proc(m: RegexMatch): string =
      let holder = m.captures[0]
      let callback = m.captures[1]
      "this.holder===void 0&&(this.holder=" & holder &
        ",process.platform===\"linux\"&&globalThis.__linuxExecutor?.__setLockHeld?.(!0).catch?.(e=>console.warn(\"[linux-executor] failed to start bridge session on lock acquire\",e))," &
        "this.emit(\"cuLockChanged\",{holder:" & holder & "})," & callback & "())"
    )
    if n >= 1:
      echo &"  [OK] cu lock acquire: start bridge session on Linux ({n} match)"
      inc changes, n
      inc patchesApplied
    else:
      echo "  [FAIL] cu lock acquire pattern: 0 matches"

  # ── Patch 4b.2: cu lock release → __setLockHeld(false) ─────────────────
  block:
    let pat = re"""this\.holder===([\w$]+)&&\(this\.holder=void 0,this\.emit\("cuLockChanged",\{holder:void 0\}\)\)"""
    let n = replaceFirst(content, pat, proc(m: RegexMatch): string =
      let holder = m.captures[0]
      "this.holder===" & holder &
        "&&(this.holder=void 0,process.platform===\"linux\"&&globalThis.__linuxExecutor?.__setLockHeld?.(!1).catch?.(e=>console.warn(\"[linux-executor] failed to stop bridge session on lock release\",e))," &
        "this.emit(\"cuLockChanged\",{holder:void 0}))"
    )
    if n >= 1:
      echo &"  [OK] cu lock release: stop bridge session on Linux ({n} match)"
      inc changes, n
      inc patchesApplied
    else:
      echo "  [FAIL] cu lock release pattern: 0 matches"

  # ── Patch 5: ensureOsPermissions → skip TCC on Linux ───────────────────
  block:
    let pat = re"""ensureOsPermissions:([\w$]+)"""
    let n = replaceFirst(content, pat, proc(m: RegexMatch): string =
      let fnName = m.captures[0]
      &"ensureOsPermissions:process.platform===\"linux\"?async()=>({{granted:!0}}):{fnName}"
    )
    if n >= 1:
      echo &"  [OK] ensureOsPermissions: skip TCC on Linux ({n} match)"
      inc changes, n
      inc patchesApplied
    else:
      echo "  [FAIL] ensureOsPermissions pattern: 0 matches"

  # ── Patch 5b (kwin-wayland): screenshot intro note workaround ──────────
  block:
    if content.contains("linuxVisibleLastScreenshot=") and
       content.contains("lastScreenshot:linuxVisibleLastScreenshot,"):
      echo "  [OK] screenshot intro note workaround: already present"
      inc patchesApplied
    else:
      let seedPat = re"""async\(([\w$]+),[\w$]+\)=>\{[\s\S]{0,4000}?;[\w$]+\(\)\}\}const ([\w$]+)=([\w$]+)\|\|\(([\w$]+)=([\w$]+)\.getLastScreenshotDims\)==null\?void 0:\4\.call\(\5\),([\w$]+)=new AbortController,([\w$]+)=\{"""
      let maybeSeed = content.find(seedPat)
      if maybeSeed.isNone:
        echo "  [FAIL] screenshot intro note: wrapper seed anchor not found"
      else:
        let seed = maybeSeed.get()
        let toolName = seed.captures[0]
        let dimsVar = seed.captures[1]
        let lastVar = seed.captures[2]
        let injection = ",linuxVisibleLastScreenshot=process.platform===\"linux\"&&" &
          lastVar & "===void 0&&" & toolName & "===\"screenshot\"?void 0:" &
          lastVar & "??(" & dimsVar & "?{..." & dimsVar & ",base64:\"\"}:void 0)"
        let abortBounds = seed.captureBounds[5]
        let splitPoint = abortBounds.a - 1
        content = content[0..<splitPoint] & injection & content[splitPoint..^1]
        inc changes

        let lastScreenshotPat = re("lastScreenshot:" & escapeRe(lastVar) &
          r"\?\?\(" & escapeRe(dimsVar) & r"\?\{\.\.\." & escapeRe(dimsVar) &
          """,base64:""\}:void 0\),""")
        let lsCount = replaceFirst(content, lastScreenshotPat, proc(m: RegexMatch): string =
          "lastScreenshot:linuxVisibleLastScreenshot,"
        )
        if lsCount < 1:
          echo "  [FAIL] screenshot intro note: lastScreenshot anchor not found"
        else:
          inc changes
          inc patchesApplied
          echo "  [OK] screenshot intro note: first wrapper screenshot restored"

  # ── Patch 6: handleToolCall hybrid dispatch (two-step match) ───────────
  block:
    let htcStart = re"""(([\w$]+)=\{isEnabled:[\w$]+=>[\w$]+\(\),handleToolCall:async\(([\w$]+),([\w$]+),([\w$]+)\)=>\{)"""
    let maybeHtc = content.find(htcStart)
    if maybeHtc.isNone:
      echo "  [FAIL] handleToolCall pattern: 0 matches"
      quit(1)
    let htc = maybeHtc.get()
    let objName = htc.captures[1]
    let toolNameParam = htc.captures[2]
    let inputParam = htc.captures[3]
    let sessionParam = htc.captures[4]
    let injectPos = htc.matchBounds.b + 1

    let afterBrace = content[injectPos ..< min(injectPos + 2000, content.len)]
    let dispatcherPat = re("const [\\w$]+=([\\w$]+)\\(" & escapeRe(sessionParam) & """\),\{save_to_disk:""")
    let maybeDispatcher = afterBrace.find(dispatcherPat)
    if maybeDispatcher.isNone:
      echo "  [FAIL] handleToolCall dispatcher not found"
      quit(1)
    let dispatcher = maybeDispatcher.get().captures[0]
    var handlerJs = LINUX_HANDLER_INJECTION_JS.strip()
    handlerJs = handlerJs.replace("__SELF__", objName)
    handlerJs = handlerJs.replace("__DISPATCHER__", dispatcher)
    handlerJs = handlerJs.replace("__TOOL_NAME__", toolNameParam)
    handlerJs = handlerJs.replace("__INPUT__", inputParam)
    handlerJs = handlerJs.replace("__SESSION__", sessionParam)
    # Gate regular-mode handler: kwin-wayland falls through to upstream
    handlerJs = handlerJs.replace(
      "if(process.platform===\"linux\"){",
      "if(process.platform===\"linux\"&&!globalThis.__cuKwinMode){",
    )
    content = content[0..<injectPos] & handlerJs & content[injectPos..^1]
    echo "  [OK] handleToolCall: regular-mode hybrid dispatch (gated; kwin-wayland falls through to upstream)"
    inc changes
    inc patchesApplied

  # ── Patch 7: teach overlay CU gate verify (no content change) ──────────
  var overlayVarOpt: Option[string]
  block:
    let stubPat = re"""listInstalledApps:\(\)=>\[\]\}\)"""
    let maybeStub = content.find(stubPat)
    if maybeStub.isNone:
      echo "  [FAIL] teach overlay: TCC stub pattern not found"
    else:
      let stub = maybeStub.get()
      let afterStart = stub.matchBounds.b + 1
      let afterStub = content[afterStart ..< min(afterStart + 50, content.len)]
      let gatePat = re""",[\w$]+\(\)&&\("""
      if afterStub.contains(".has(process.platform)") or afterStub.find(gatePat).isSome:
        echo "  [OK] teach overlay controller: CU gate found (handled by Set fix)"
        inc patchesApplied
      else:
        echo "  [FAIL] teach overlay: CU gate not found after TCC stub"

  # ── Patch 7b (kwin-wayland): teach overlay bridge-backed init ──────────
  block:
    if content.contains("globalThis.__linuxExecutor?.__initTeachController"):
      echo "  [OK] teach overlay controller: bridge-backed init already present"
      inc patchesApplied
    else:
      let markerIdx = findStringMarker(content, "[cu-teach] controller initialized")
      if markerIdx == -1:
        echo "  [FAIL] teach overlay controller marker: not found"
      else:
        let fnInfoOpt = findFunctionBeforeMarker(content, markerIdx)
        if fnInfoOpt.isNone:
          echo "  [FAIL] teach overlay controller init header: not found"
        else:
          let fnInfo = fnInfoOpt.get
          let headerPat = re"""^function [\w$]+\(([\w$]+),([\w$]+)\)\{$"""
          let headerMatch = fnInfo.header.find(headerPat)
          let bodyOK = fnInfo.body.contains(".on(\"teachModeChanged\"") and
                       fnInfo.body.contains(".on(\"teachStepRequested\"")
          if headerMatch.isNone or not bodyOK:
            echo "  [FAIL] teach overlay controller init function shape: unexpected"
          else:
            let manager = headerMatch.get().captures[0]
            let mainWindow = headerMatch.get().captures[1]
            let injected = &"if(process.platform===\"linux\"&&globalThis.__linuxExecutor?.__initTeachController){{globalThis.__linuxExecutor.__initTeachController({manager},{mainWindow});return;}}"
            content = content[0..fnInfo.headerEnd] & injected &
                      content[fnInfo.headerEnd + 1..^1]
            echo "  [OK] teach overlay controller: Linux bridge-backed init"
            inc changes
            inc patchesApplied

  # ── Patch 7c (kwin-wayland): side-panel bridge-backed init ─────────────
  block:
    if content.contains("globalThis.__linuxExecutor?.__initDockController"):
      echo "  [OK] cu side-panel: bridge-backed init already present"
      inc patchesApplied
    else:
      let markerIdx = findStringMarker(content, "[cu-side-panel] initialized")
      if markerIdx == -1:
        echo "  [FAIL] cu side-panel controller marker: not found"
      else:
        let fnInfoOpt = findFunctionBeforeMarker(content, markerIdx)
        if fnInfoOpt.isNone:
          echo "  [FAIL] cu side-panel controller init header: not found"
        else:
          let fnInfo = fnInfoOpt.get
          let headerPat = re"""^function [\w$]+\(([\w$]+)\)\{$"""
          let headerMatch = fnInfo.header.find(headerPat)
          let bodyOK = fnInfo.body.contains(".on(\"cuLockChanged\"")
          if headerMatch.isNone or not bodyOK:
            echo "  [FAIL] cu side-panel controller init function shape: unexpected"
          else:
            let mainWindow = headerMatch.get().captures[0]
            let injected = &"if(process.platform===\"linux\"&&globalThis.__linuxExecutor?.__initDockController){{globalThis.__linuxExecutor.__initDockController({mainWindow});return;}}"
            content = content[0..fnInfo.headerEnd] & injected &
                      content[fnInfo.headerEnd + 1..^1]
            echo "  [OK] cu side-panel: Linux bridge-backed init"
            inc changes
            inc patchesApplied

  # ── Patch 8: teach overlay mouse — tooltip-bounds polling on Linux ─────
  var overlayVar: string
  block:
    let overlayVarPat = re"""([\w$]+)\.setAlwaysOnTop\(!0,"screen-saver"\),\1\.setFullScreenable\(!1\),\1\.setIgnoreMouseEvents\(!0,\{forward:!0\}\)"""
    let maybeOV = content.find(overlayVarPat)
    if maybeOV.isNone:
      echo "  [FAIL] teach overlay mouse: overlay variable pattern not found"
    else:
      overlayVar = maybeOV.get().captures[0]
      overlayVarOpt = some(overlayVar)
      let oldInit = overlayVar & ".setIgnoreMouseEvents(!0,{forward:!0})"
      let newInit = "(process.platform===\"linux\"?(" & overlayVar &
        ".setIgnoreMouseEvents=function(){},globalThis.__isVM&&" & overlayVar &
        ".setOpacity(.15)):" & overlayVar & ".setIgnoreMouseEvents(!0,{forward:!0}))"
      if replaceLiteralFirst(content, oldInit, newInit) == 1:
        echo &"  [OK] teach overlay mouse: tooltip-bounds polling for Linux ({overlayVar})"
        inc changes
        inc patchesApplied
      else:
        echo "  [FAIL] teach overlay mouse: replacement failed"

  # ── Patch 8a (kwin-wayland): disable glow overlay ──────────────────────
  block:
    let pat = re"""(function [\w$]+\(([\w$]+),([\w$]+)\)\{)([\w$]+)\.on\("cuLockChanged","""
    let n = replaceFirst(content, pat, proc(m: RegexMatch): string =
      m.captures[0] &
        "if(process.platform===\"linux\"&&globalThis.__cuKwinMode)return;" &
        m.captures[3] & ".on(\"cuLockChanged\","
    )
    if n >= 1:
      echo &"  [OK] cu glow overlay: disabled in kwin-wayland mode ({n} match)"
      inc changes, n
      inc patchesApplied
    else:
      echo "  [FAIL] cu glow overlay pattern: 0 matches"

  # ── Patch 9a: neutralize setIgnoreMouseEvents in yJt ───────────────────
  if overlayVarOpt.isSome:
    block:
      let pat = re"""(function [\w$]+\([\w$]+,[\w$]+\)\{)([\w$]+)(\.setIgnoreMouseEvents\(!0,\{forward:!0\}\))"""
      let n = replaceFirst(content, pat, proc(m: RegexMatch): string =
        let fnHead = m.captures[0]
        let vvar = m.captures[1]
        let rest = m.captures[2]
        &"{fnHead}(process.platform!==\"linux\"&&{vvar}{rest})"
      )
      if n >= 1:
        echo "  [OK] teach overlay: neutralized setIgnoreMouseEvents in show handler (yJt) for Linux"
        inc changes
        inc patchesApplied
      else:
        echo "  [FAIL] teach overlay: yJt pattern not found"

    # ── Patch 9b: neutralize setIgnoreMouseEvents in SUn ─────────────────
    block:
      let ov = overlayVarOpt.get
      let sunPat = ov & ".setIgnoreMouseEvents(!0,{forward:!0})," & ov &
                   ".webContents.send(\"cu-teach:working\""
      let sunRepl = "(process.platform!==\"linux\"&&" & ov &
                    ".setIgnoreMouseEvents(!0,{forward:!0}))," & ov &
                    ".webContents.send(\"cu-teach:working\""
      if replaceLiteralFirst(content, sunPat, sunRepl) == 1:
        echo "  [OK] teach overlay: neutralized setIgnoreMouseEvents in working handler (SUn) for Linux"
        inc changes
        inc patchesApplied
      else:
        echo "  [FAIL] teach overlay: SUn pattern not found"

  # ── Patch 10: teach overlay VM-aware transparency ──────────────────────
  block:
    let pat = re"""(=new [\w$]+\.BrowserWindow\(\{[^}]*?)transparent:!0([^}]*?)backgroundColor:"#00000000""""
    var applied = false
    for m in content.findIter(pat):
      let matchStart = m.matchBounds.a
      let preStart = max(0, matchStart - 80)
      let before = content[preStart..<matchStart]
      if before.contains("workArea"):
        let bounds = m.matchBounds
        let old = content[bounds.a..bounds.b]
        var newS = old
        newS = newS.replace("transparent:!0", "transparent:!globalThis.__isVM")
        newS = newS.replace("backgroundColor:\"#00000000\"",
                            "backgroundColor:globalThis.__isVM?\"#000000\":\"#00000000\"")
        discard replaceLiteralFirst(content, old, newS)
        echo "  [OK] teach overlay: VM-aware transparency (transparent on native, dark backdrop on VMs)"
        inc changes
        inc patchesApplied
        applied = true
        break
    if not applied:
      echo "  [FAIL] teach overlay transparency pattern not found"

  # ── Patch 10b: xlr() force primary monitor on Linux ────────────────────
  block:
    let pat = re"""(function [\w$]+\(([\w$]+)\)\{)(return \2===null\?[\w$]+\.screen\.getPrimaryDisplay\(\):[\w$]+\.screen\.getAllDisplays\(\)\.find)"""
    let n = replaceFirst(content, pat, proc(m: RegexMatch): string =
      let param = m.captures[1]
      m.captures[0] & &"if(process.platform===\"linux\"){param}=null;" & m.captures[2]
    )
    if n >= 1:
      echo &"  [OK] teach overlay display: forced to primary monitor on Linux ({n} match)"
      inc changes, n
      inc patchesApplied
    else:
      echo "  [FAIL] xlr display resolver pattern: 0 matches"

  # ── Patch 11: force mVt() → true on Linux ──────────────────────────────
  block:
    let pat = re"""(function [\w$]+\(\)\{)return [\w$]+\([\w$]+\)\?[\w$]+\.has\(process\.platform\)&&[\w$]+\(\):[\w$]+\(\)\}"""
    let n = replaceFirst(content, pat, proc(m: RegexMatch): string =
      let bounds = m.matchBounds
      let whole = content[bounds.a..bounds.b]
      let headerLen = m.captures[0].len
      m.captures[0] & "if(process.platform===\"linux\")return!0;" & whole[headerLen..^1]
    )
    if n >= 1:
      echo &"  [OK] mVt isEnabled: force true on Linux ({n} match)"
      inc changes, n
      inc patchesApplied
    else:
      echo "  [FAIL] mVt isEnabled pattern: 0 matches"

  # ── Patch 12: force rj() → true on Linux ───────────────────────────────
  block:
    let pat = re"""(function [\w$]+\(\)\{)return [\w$]+\.has\(process\.platform\)\?[\w$]+\(\)&&[\w$]+\("chicagoEnabled"\):!1\}"""
    let n = replaceFirst(content, pat, proc(m: RegexMatch): string =
      let bounds = m.matchBounds
      let whole = content[bounds.a..bounds.b]
      let headerLen = m.captures[0].len
      m.captures[0] & "if(process.platform===\"linux\")return!0;" & whole[headerLen..^1]
    )
    if n >= 1:
      echo &"  [OK] rj chicagoEnabled bypass: force true on Linux ({n} match)"
      inc changes, n
      inc patchesApplied
    else:
      echo "  [FAIL] rj pattern: 0 matches"

  # ─── Tool description patches ────────────────────────────────────────
  echo "  --- Tool description patches (non-fatal) ---"
  var descChanges = 0

  # 13a: Lf allowlist gate → empty on Linux
  block:
    let pat = re"""([\w$]+)="The frontmost application must be in the session allowlist at the time of this call, or this tool returns an error and does nothing\.""""
    let n = replaceFirst(content, pat, proc(m: RegexMatch): string =
      let v = m.captures[0]
      &"{v}=process.platform===\"linux\"?\"\":\"The frontmost application must be in the session allowlist at the time of this call, or this tool returns an error and does nothing.\""
    )
    if n >= 1:
      echo "  [OK] 13a Lf allowlist gate: empty on Linux"
      inc descChanges
      inc patchesApplied
    else:
      echo "  [FAIL] 13a Lf: not found"

  # 13b: request_access macOS prefix → 3-way ternary (kwin/regular/macOS)
  block:
    let old13b = """'This computer is running macOS. The file manager is "Finder". '"""
    let new13b =
      "(process.platform===\"linux\"?(globalThis.__cuKwinMode?" &
      "'This computer is running Linux with KDE Plasma. The file manager is \\\"Dolphin\\\". '" &
      ":" &
      "'This computer is running Linux. " &
      "On Linux, ALL applications are automatically accessible at full " &
      "tier without explicit permission grants. You do NOT need to call " &
      "request_access before using other tools. If called, it returns " &
      "synthetic grant confirmations. The file manager depends on the " &
      "desktop environment (e.g. Nautilus on GNOME, Dolphin on KDE, " &
      "Thunar on XFCE). ')" &
      ":" &
      "'This computer is running macOS. The file manager is \"Finder\". ')"
    if replaceLiteralFirst(content, old13b, new13b) == 1:
      echo "  [OK] 13b request_access: 3-way (kwin-wayland=KDE/Dolphin, regular=generic Linux, other=macOS)"
      inc descChanges
      inc patchesApplied
    else:
      echo "  [FAIL] 13b request_access macOS prefix: not found"

  # 13b.kwin-alias: plasmashell alias in request_access
  block:
    let pat = re"""(const ([\w$]+)=[\w$]+\.apps;if\(!Array\.isArray\(\2\)\|\|!\2\.every\(([\w$]+)=>typeof \3=="string"\)\)return [\w$]+\('"apps" must be an array of strings\.',"bad_args"\);const )([\w$]+)=\2(,[\w$]+=\{\};)"""
    let n = replaceFirst(content, pat, proc(m: RegexMatch): string =
      let prefix = m.captures[0]
      let appsVar = m.captures[1]
      let mappedVar = m.captures[3]
      let suffix = m.captures[4]
      prefix & mappedVar & "=globalThis.__cuKwinMode?" & appsVar &
        ".map(v=>v===\"org.kde.plasmashell\"?\"plasmashell\":v):" & appsVar & suffix
    )
    if n >= 1:
      echo "  [OK] 13b.kwin-alias request_access: org.kde.plasmashell -> plasmashell (kwin-wayland mode)"
      inc descChanges
      inc patchesApplied
    else:
      echo "  [FAIL] 13b.kwin-alias request_access alias: not found"

  # 13b.kwin-alias-teach: plasmashell alias in request_teach_access
  block:
    let pat = re"""(const ([\w$]+)=[\w$]+\.apps;if\(!Array\.isArray\(\2\)\|\|!\2\.every\(([\w$]+)=>typeof \3=="string"\)\)return [\w$]+\('"apps" must be an array of strings\.',"bad_args"\);const )([\w$]+)=\2(,\{needDialog:)"""
    let n = replaceFirst(content, pat, proc(m: RegexMatch): string =
      let prefix = m.captures[0]
      let appsVar = m.captures[1]
      let mappedVar = m.captures[3]
      let suffix = m.captures[4]
      prefix & mappedVar & "=globalThis.__cuKwinMode?" & appsVar &
        ".map(v=>v===\"org.kde.plasmashell\"?\"plasmashell\":v):" & appsVar & suffix
    )
    if n >= 1:
      echo "  [OK] 13b.kwin-alias-teach request_teach_access: plasmashell alias (kwin-wayland mode)"
      inc descChanges
      inc patchesApplied
    else:
      echo "  [FAIL] 13b.kwin-alias-teach request_teach_access alias: not found"

  # 13b.kwin-shell-hint: desktop shell hint template
  block:
    let prefix = "`The desktop shell is frontmost. Double-click, right-click, and Enter on desktop items can launch applications outside the allowlist. To interact with the desktop, taskbar, Start menu, Search, or file manager, call request_access with exactly \"${"
    let suffix = "===\"win32\"?\"File Explorer\":\"Finder\"}\" in the apps array \xe2\x80\x94 that single grant covers all of them. To interact with a different app, use open_application to bring it forward.`"
    let pat = re(escapeRe(prefix) & "([\\w$]+)" & escapeRe(suffix))
    let maybeMatch = content.find(pat)
    if maybeMatch.isSome:
      let m = maybeMatch.get()
      let platVar = m.captures[0]
      let newShell =
        "`${globalThis.__cuKwinMode?`The desktop shell is frontmost. Desktop icons, panels, launchers, and widgets belong to Plasma Shell. To interact with them, call request_access with exactly \\\"plasmashell\\\" in the apps array. If you need the file manager, request \\\"Dolphin\\\" separately. To interact with a different app, use open_application to bring it forward.`:`The desktop shell is frontmost. Double-click, right-click, and Enter on desktop items can launch applications outside the allowlist. To interact with the desktop, taskbar, Start menu, Search, or file manager, call request_access with exactly \\\"${" &
        platVar & "===\"win32\"?\"File Explorer\":\"Finder\"}\\\" in the apps array \xe2\x80\x94 that single grant covers all of them. To interact with a different app, use open_application to bring it forward.`}`"
      let bounds = m.matchBounds
      let old = content[bounds.a..bounds.b]
      discard replaceLiteralFirst(content, old, newShell)
      echo "  [OK] 13b.kwin-shell-hint: kwin-wayland=plasmashell, regular/other=upstream wording"
      inc descChanges
      inc patchesApplied
    else:
      echo "  [FAIL] 13b.kwin-shell-hint desktop shell hint: not found"

  # 13b.kwin-shell-grant: shell grant predicate
  block:
    let pat = re"""(function [\w$]+\(([\w$]+),([\w$]+)\)\{)return \3==="darwin"\?\2\.some\(([\w$]+)=>\4\.bundleId===([\w$]+)\):\2\.some\(([\w$]+)=>\6\.bundleId\.toLowerCase\(\)===([\w$]+)\)\}"""
    let n = replaceFirst(content, pat, proc(m: RegexMatch): string =
      let header = m.captures[0]
      let apps = m.captures[1]
      let plat = m.captures[2]
      let darwinIter = m.captures[3]
      let macConst = m.captures[4]
      let winIter = m.captures[5]
      let winConst = m.captures[6]
      header & "return " & plat & "===\"darwin\"?" & apps & ".some(" & darwinIter &
        "=>" & darwinIter & ".bundleId===" & macConst &
        "):globalThis.__cuKwinMode&&" & plat & "===\"linux\"?" & apps & ".some(" &
        darwinIter & "=>" & darwinIter & ".bundleId===\"plasmashell\"||" &
        darwinIter & ".bundleId===\"org.kde.plasmashell\"):" & apps & ".some(" &
        winIter & "=>" & winIter & ".bundleId.toLowerCase()===" & winConst & ")}"
    )
    if n >= 1:
      echo "  [OK] 13b.kwin-shell-grant: plasmashell satisfies shell access (kwin-wayland only)"
      inc descChanges
      inc patchesApplied
    else:
      echo "  [FAIL] 13b.kwin-shell-grant desktop shell grant predicate: not found"

  # 13b.kwin-shell-detect: shell detection
  block:
    let pat = re"""(function [\w$]+\(([\w$]+)\)\{)return \2===([\w$]+)\?!0:!([\w$]+)\|\|!([\w$]+)\.has\(([\w$]+)\(\2\)\)\?!1:\2\.toLowerCase\(\)\.startsWith\(\4\)\}"""
    let n = replaceFirst(content, pat, proc(m: RegexMatch): string =
      let header = m.captures[0]
      let arg = m.captures[1]
      let macConst = m.captures[2]
      let winPrefix = m.captures[3]
      let winSet = m.captures[4]
      let winNorm = m.captures[5]
      header & "return " & arg & "===" & macConst & "||globalThis.__cuKwinMode&&(" &
        arg & "===\"plasmashell\"||" & arg & "===\"org.kde.plasmashell\")?!0:!" &
        winPrefix & "||!" & winSet & ".has(" & winNorm & "(" & arg & "))?!1:" &
        arg & ".toLowerCase().startsWith(" & winPrefix & ")}"
    )
    if n >= 1:
      echo "  [OK] 13b.kwin-shell-detect: plasmashell recognized as shell (kwin-wayland only)"
      inc descChanges
      inc patchesApplied
    else:
      echo "  [FAIL] 13b.kwin-shell-detect desktop shell detection: not found"

  # 13c: request_access apps — WM_CLASS for Linux
  block:
    let old13c = """'Application display names (e.g. "Slack", "Calendar") or bundle identifiers (e.g. "com.tinyspeck.slackmacgap"). Display names are resolved case-insensitively against installed apps.'"""
    let new13c =
      "(process.platform===\"linux\"?" &
      "'Application names as shown in window titles, or WM_CLASS values " &
      "(e.g. \"firefox\", \"org.gnome.Nautilus\"). " &
      "On Linux all apps are auto-granted at full tier.'" &
      ":" &
      "'Application display names (e.g. \"Slack\", \"Calendar\") or bundle " &
      "identifiers (e.g. \"com.tinyspeck.slackmacgap\"). Display names are " &
      "resolved case-insensitively against installed apps.')"
    if replaceLiteralFirst(content, old13c, new13c) == 1:
      echo "  [OK] 13c request_access apps: Linux identifiers"
      inc descChanges
      inc patchesApplied
    else:
      echo "  [FAIL] 13c request_access apps: not found"

  # 13d: open_application app identifier
  block:
    let old13d = """'Display name (e.g. "Slack") or bundle identifier (e.g. "com.tinyspeck.slackmacgap").'"""
    let new13d =
      "(process.platform===\"linux\"?" &
      "'Application name or WM_CLASS (e.g. \"firefox\", \"nautilus\").'" &
      ":" &
      "'Display name (e.g. \"Slack\") or bundle identifier (e.g. \"com.tinyspeck.slackmacgap\").')"
    if replaceLiteralFirst(content, old13d, new13d) == 1:
      echo "  [OK] 13d open_application app: Linux identifiers"
      inc descChanges
      inc patchesApplied
    else:
      echo "  [FAIL] 13d open_application app: not found"

  # 13e: open_application description — no allowlist on Linux
  block:
    let old13e = "\"Bring an application to the front, launching it if necessary. The target application must already be in the session allowlist \xe2\x80\x94 call request_access first.\""
    let new13e =
      "(process.platform===\"linux\"?" &
      "\"Bring an application to the front, launching it if necessary. " &
      "On Linux, all applications are directly accessible.\"" &
      ":" &
      "\"Bring an application to the front, launching it if necessary. " &
      "The target application must already be in the session allowlist " &
      "\xe2\x80\x94 call request_access first.\")"
    if replaceLiteralFirst(content, old13e, new13e) == 1:
      echo "  [OK] 13e open_application: no allowlist on Linux"
      inc descChanges
      inc patchesApplied
    else:
      echo "  [FAIL] 13e open_application: not found"

  # 13f: screenshot description — clean on Linux
  block:
    let old13f = "\"Take a screenshot of the primary display. On this platform, screenshots are NOT filtered \xe2\x80\x94 all open windows are visible. Input actions targeting apps not in the session allowlist are rejected.\""
    let new13f =
      "(process.platform===\"linux\"?" &
      "\"Take a screenshot of the primary display. All open windows are visible.\"" &
      ":" &
      "\"Take a screenshot of the primary display. On this platform, " &
      "screenshots are NOT filtered \xe2\x80\x94 all open windows are visible. " &
      "Input actions targeting apps not in the session allowlist are rejected.\")"
    if replaceLiteralFirst(content, old13f, new13f) == 1:
      echo "  [OK] 13f screenshot: clean description on Linux"
      inc descChanges
      inc patchesApplied
    else:
      echo "  [FAIL] 13f screenshot: not found"

  # 13g: screenshot suffix — no allowlist error on Linux
  block:
    let pat = re"""([\w$]+)\+" Returns an error if the allowlist is empty\. The returned image is what subsequent click coordinates are relative to\.""""
    let n = replaceFirst(content, pat, proc(m: RegexMatch): string =
      let v = m.captures[0]
      &"{v}+(process.platform===\"linux\"" &
        "?\" The returned image is what subsequent click coordinates are relative to.\"" &
        ":\" Returns an error if the allowlist is empty. The returned image is what subsequent click coordinates are relative to.\")"
    )
    if n >= 1:
      echo "  [OK] 13g screenshot suffix: no allowlist error on Linux"
      inc descChanges
      inc patchesApplied
    else:
      echo "  [FAIL] 13g screenshot suffix: not found"

  if descChanges > 0:
    inc changes, descChanges
    echo &"  [OK] {descChanges}/12 description patches applied (7 regular + 5 kwin-wayland KDE)"
  else:
    echo "  [FAIL] No description patches applied (descriptions unchanged)"

  # ─── Patch 14: Linux-aware CU system prompt ──────────────────────────
  # 14a: separate filesystems → 3-way same-filesystem wording (2 occurrences)
  block:
    let sepOldFull = "**Separate filesystems.** Computer-use actions (clicks, typing, clipboard writes) happen on the user's real computer \xe2\x80\x94 a different system from your sandbox. "
    let sepCount = countOccurrences(content, sepOldFull)
    if sepCount >= 2:
      let sepNewFull =
        "${process.platform===\"linux\"?(globalThis.__cuKwinMode" &
        "?\"**Same filesystem.** Computer-use actions and your CLI tools operate on the same Linux machine. " &
        "Files you create are directly accessible to desktop applications, and files selected or edited in " &
        "desktop apps are on the same machine you can read from the CLI. " &
        "\"" &
        ":\"**Same filesystem.** Computer-use actions and your CLI tools operate on the same Linux machine. " &
        "There is no sandbox \\u2014 files you create are directly accessible to desktop applications and vice versa. " &
        "\")" &
        ":\"**Separate filesystems.** Computer-use actions (clicks, typing, clipboard writes) " &
        "happen on the user's real computer \xe2\x80\x94 a different system from your sandbox. " &
        "\"}"
      discard replaceLiteralAll(content, sepOldFull, sepNewFull)
      echo &"  [OK] 14a separate filesystems: 3-way replace, {sepCount} occurrences"
      inc changes, sepCount
      inc patchesApplied
    else:
      echo &"  [FAIL] 14a separate filesystems: expected 2 occurrences, found {sepCount}"

  # 14b: Finder/Photos/System Settings → generic Linux app terms
  block:
    let appsOld = "Maps, Notes, Finder, Photos, System Settings"
    let appsNew = "${process.platform===\"linux\"?\"the file manager, image viewer, terminal emulator, system settings\":\"Maps, Notes, Finder, Photos, System Settings\"}"
    if replaceLiteralFirst(content, appsOld, appsNew) == 1:
      echo "  [OK] 14b app names: replaced macOS apps with Linux-generic terms"
      inc changes
      inc patchesApplied
    else:
      echo "  [FAIL] 14b app names: not found"

  # 14c: File Explorer/Finder → 3-way (Dolphin/Files/Finder)
  block:
    let fmOld = "\"File Explorer\":\"Finder\""
    let fmNew = "\"File Explorer\":process.platform===\"linux\"?(globalThis.__cuKwinMode?\"Dolphin\":\"Files\"):\"Finder\""
    if replaceLiteralFirst(content, fmOld, fmNew) == 1:
      echo "  [OK] 14c file manager name: 3-way (kwin-wayland=Dolphin, regular=Files, other=Finder)"
      inc changes
      inc patchesApplied
    else:
      echo "  [FAIL] 14c file manager name: pattern not found"

  # 14d (kwin-wayland): env prompt KDE augmentation
  block:
    let envPat = re"""You have a computer-use MCP available \(tools named \\`mcp__computer-use__\*\\`\)\. It lets you take screenshots of the user's desktop and control it with mouse clicks, keyboard input, and scrolling\."""
    let envNew =
      "You have a computer-use MCP available (tools named \\`mcp__computer-use__*\\`). It lets you take " &
      "screenshots of the user's desktop and control it with mouse clicks, keyboard input, and scrolling." &
      "${globalThis.__cuKwinMode?' This computer is running Linux with KDE Plasma. The desktop shell is " &
      "plasmashell. The file manager is Dolphin.':''}"
    let envCount = replaceAllRegex(content, envPat, proc(m: RegexMatch): string = envNew)
    if envCount > 0:
      let plural = if envCount != 1: "s" else: ""
      echo &"  [OK] 14d CU env prompt: kwin-wayland-only KDE suffix ({envCount} occurrence{plural})"
      inc changes, envCount
      inc patchesApplied
    else:
      echo "  [FAIL] 14d CU env prompt: environment sentence anchor not found"

  # Final check
  if patchesApplied < EXPECTED_PATCHES:
    echo &"  [FAIL] Only {patchesApplied}/{EXPECTED_PATCHES} patches applied -- check [FAIL] messages above"
    # Still write partial changes so the build can be inspected
    quit(1)

  return content

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_computer_use_linux <path_to_index.js>"
    quit(1)

  let filePath = paramStr(1)
  echo "=== Patch: fix_computer_use_linux ==="
  echo "  Target: " & filePath

  if not fileExists(filePath):
    echo "  [FAIL] File not found: " & filePath
    quit(1)

  let input = readFile(filePath)
  let output = apply(input)

  if output != input:
    writeFile(filePath, output)
    echo &"  [PASS] {EXPECTED_PATCHES}/{EXPECTED_PATCHES} sub-patches applied ({output.len - input.len} bytes added)"
  else:
    echo "  [FAIL] No changes made"
    quit(1)
