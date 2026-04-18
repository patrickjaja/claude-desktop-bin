# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
#
# Make computer-use work on Linux by removing platform gates and providing
# a Linux executor.
#
# 23 sub-patches covering:
#   1  Linux executor injection at app.on("ready")
#   2  ese Set: add "linux"
#   4  createDarwinExecutor: Linux fallback
#   5  ensureOsPermissions: skip TCC on Linux
#   6  handleToolCall: hybrid dispatch
#   7  teach overlay controller: verify CU gate
#   8  teach overlay mouse: tooltip-bounds polling
#   9a teach overlay: neutralize setIgnoreMouseEvents in yJt
#   9b teach overlay: neutralize setIgnoreMouseEvents in SUn
#  10  teach overlay: VM-aware transparency
#  10b teach overlay display: force primary monitor
#  11  mVt isEnabled: force true on Linux
#  12  rj chicagoEnabled bypass: force true on Linux
#  13a-13g: Tool description patches (7 sub-patches)
#  14a-14c: System prompt patches (3 sub-patches)

import std/[os, strformat, strutils]
import std/nre

# Extracted JS loaded via staticRead
const LINUX_EXECUTOR_JS = staticRead("../js/cu_linux_executor.js")
const LINUX_HANDLER_INJECTION_JS = staticRead("../js/cu_handler_injection.js")

const EXPECTED_PATCHES = 23

proc apply*(input: string): string =
  result = input
  var changes = 0
  var patchesApplied = 0

  # Patch 1: Inject Linux executor at app.on("ready")
  let readyPattern = re"""app\.on\("ready",async\(\)=>\{"""
  var count1 = 0
  result = result.replace(readyPattern, proc(m: RegexMatch): string =
    inc count1
    if count1 > 1: return m.match
    m.match & "if(process.platform===\"linux\"){" & LINUX_EXECUTOR_JS & "}"
  )
  if count1 >= 1:
    echo &"  [OK] Linux executor: injected ({count1} match)"
    changes += count1
    inc patchesApplied
  else:
    echo "  [FAIL] app.on(\"ready\") pattern: 0 matches"
    quit(1)

  # Patch 2: Add "linux" to the computer-use platform Set
  let setOld = "new Set([\"darwin\",\"win32\"])"
  let setNew = "new Set([\"darwin\",\"win32\",\"linux\"])"
  let count2 = result.count(setOld)
  if count2 >= 1:
    result = result.replace(setOld, setNew)
    echo &"  [OK] ese Set: added linux ({count2} match(es))"
    changes += count2
    inc patchesApplied
  else:
    let setAlready = result.count(setNew)
    if setAlready >= 1:
      echo &"  [OK] ese Set: linux already present in all {setAlready} Set(s)"
      inc patchesApplied
    else:
      echo "  [FAIL] ese Set pattern: 0 matches"
      quit(1)

  # Patch 4: Patch createDarwinExecutor to return Linux executor on Linux
  let executorPattern = re"""(function [\w$]+\([\w$]+\)\{)if\(process\.platform!=="darwin"\)throw new Error"""
  var count4 = 0
  result = result.replace(executorPattern, proc(m: RegexMatch): string =
    inc count4
    if count4 > 1: return m.match
    m.captures[0] & "if(process.platform===\"linux\"&&globalThis.__linuxExecutor)return globalThis.__linuxExecutor;" &
      "if(process.platform!==\"darwin\")throw new Error"
  )
  if count4 >= 1:
    echo &"  [OK] createDarwinExecutor: Linux fallback ({count4} match)"
    changes += count4
    inc patchesApplied
  else:
    echo "  [FAIL] createDarwinExecutor pattern: 0 matches"
    quit(1)

  # Patch 5: Patch ensureOsPermissions to return granted:true on Linux
  let permsPattern = re"ensureOsPermissions:([\w$]+)"
  var count5 = 0
  result = result.replace(permsPattern, proc(m: RegexMatch): string =
    inc count5
    if count5 > 1: return m.match
    let fnName = m.captures[0]
    "ensureOsPermissions:process.platform===\"linux\"?async()=>({granted:!0}):" & fnName
  )
  if count5 >= 1:
    echo &"  [OK] ensureOsPermissions: skip TCC on Linux ({count5} match)"
    changes += count5
    inc patchesApplied
  else:
    echo "  [FAIL] ensureOsPermissions pattern: 0 matches"

  # Patch 6: Hybrid handleToolCall -- inject early-return block
  # Step A: Match the handleToolCall start
  let htcStart = re"(([\w$]+)=\{isEnabled:[\w$]+=>[\w$]+\(\),handleToolCall:async\(([\w$]+),([\w$]+),([\w$]+)\)=>\{)"
  let htcMatch = result.find(htcStart)

  if htcMatch.isSome:
    let m = htcMatch.get()
    let objName = m.captures[1]
    let toolNameParam = m.captures[2]
    let inputParam = m.captures[3]
    let sessionParam = m.captures[4]
    let injectPos = m.matchBounds.b + 1  # right after the opening {

    # Step B: Find the dispatcher function name
    let afterBrace = result[injectPos .. min(injectPos + 2000, result.len - 1)]
    let dispatcherSearch = re("const [\\w$]+=([\\w$]+)\\(" & sessionParam & "\\),\\{save_to_disk:")
    let dispatcherMatch = afterBrace.find(dispatcherSearch)

    if dispatcherMatch.isSome:
      let dispatcher = dispatcherMatch.get().captures[0]
      var handlerJs = LINUX_HANDLER_INJECTION_JS
      handlerJs = handlerJs.replace("__SELF__", objName)
      handlerJs = handlerJs.replace("__DISPATCHER__", dispatcher)
      handlerJs = handlerJs.replace("__TOOL_NAME__", toolNameParam)
      handlerJs = handlerJs.replace("__INPUT__", inputParam)
      handlerJs = handlerJs.replace("__SESSION__", sessionParam)
      result = result[0 ..< injectPos] & handlerJs & result[injectPos .. ^1]
      echo "  [OK] handleToolCall: hybrid dispatch (teach->upstream, rest->direct) (1 match)"
      changes += 1
      inc patchesApplied
    else:
      echo "  [FAIL] handleToolCall dispatcher not found"
      quit(1)
  else:
    echo "  [FAIL] handleToolCall pattern: 0 matches"
    quit(1)

  # Patch 7: Teach overlay controller init on Linux
  let stubEnd = re"listInstalledApps:\(\)=>\[\]\}\)"
  let stubMatch = result.find(stubEnd)
  if stubMatch.isSome:
    let afterStub = result[stubMatch.get().matchBounds.b + 1 .. min(stubMatch.get().matchBounds.b + 50, result.len - 1)]
    if ".has(process.platform)" in afterStub or afterStub.find(re",[\w$]+\(\)&&\(").isSome:
      echo "  [OK] teach overlay controller: CU gate found (handled by Set fix)"
      inc patchesApplied
    else:
      echo "  [FAIL] teach overlay: CU gate not found after TCC stub"
  else:
    echo "  [FAIL] teach overlay: TCC stub pattern not found"

  # Patch 8: Fix teach overlay mouse events on Linux
  let overlayVarPattern = re"""([\w$]+)\.setAlwaysOnTop\(!0,"screen-saver"\),\1\.setFullScreenable\(!1\),\1\.setIgnoreMouseEvents\(!0,\{forward:!0\}\)"""
  let overlayVarMatch = result.find(overlayVarPattern)
  var overlayVar = ""

  if overlayVarMatch.isSome:
    overlayVar = overlayVarMatch.get().captures[0]
    let oldInit = overlayVar & ".setIgnoreMouseEvents(!0,{forward:!0})"
    let newInit =
      "(process.platform===\"linux\"?" &
      "(" & overlayVar & ".setIgnoreMouseEvents=function(){}," &
      "globalThis.__isVM&&" & overlayVar & ".setOpacity(.15))" &
      ":" & overlayVar & ".setIgnoreMouseEvents(!0,{forward:!0}))"

    let idx = result.find(oldInit)
    if idx >= 0:
      result = result[0 ..< idx] & newInit & result[idx + oldInit.len .. ^1]
      echo &"  [OK] teach overlay mouse: tooltip-bounds polling for Linux ({overlayVar})"
      changes += 1
      inc patchesApplied
    else:
      echo "  [FAIL] teach overlay mouse: replacement failed"
  else:
    echo "  [FAIL] teach overlay mouse: overlay variable pattern not found"

  # Patch 9a: Neutralize setIgnoreMouseEvents in yJt
  if overlayVar != "":
    let yjtPat = re"(function [\w$]+\([\w$]+,[\w$]+\)\{)([\w$]+)(\.setIgnoreMouseEvents\(!0,\{forward:!0\}\))"
    var yjtCount = 0
    result = result.replace(yjtPat, proc(m: RegexMatch): string =
      inc yjtCount
      if yjtCount > 1: return m.match
      let fnHead = m.captures[0]
      let varName = m.captures[1]
      let rest = m.captures[2]
      fnHead & "(process.platform!==\"linux\"&&" & varName & rest & ")"
    )
    if yjtCount >= 1:
      echo "  [OK] teach overlay: neutralized setIgnoreMouseEvents in show handler (yJt) for Linux"
      changes += 1
      inc patchesApplied
    else:
      echo "  [FAIL] teach overlay: yJt pattern not found"

    # Patch 9b: Neutralize setIgnoreMouseEvents in SUn
    let sunPat = overlayVar & ".setIgnoreMouseEvents(!0,{forward:!0})," & overlayVar & ".webContents.send(\"cu-teach:working\""
    let sunRepl = "(process.platform!==\"linux\"&&" & overlayVar & ".setIgnoreMouseEvents(!0,{forward:!0}))," & overlayVar & ".webContents.send(\"cu-teach:working\""
    if sunPat in result:
      result = result.replace(sunPat, sunRepl)
      echo "  [OK] teach overlay: neutralized setIgnoreMouseEvents in working handler (SUn) for Linux"
      changes += 1
      inc patchesApplied
    else:
      echo "  [FAIL] teach overlay: SUn pattern not found"

  # Patch 10: Fix teach overlay transparency on VMs
  let teachOverlayPattern = re"(=new [\w$]+\.BrowserWindow\(\{[^}]*?)transparent:!0([^}]*?)backgroundColor:""#00000000"""
  var pos10 = 0
  var found10 = false
  while true:
    let m = result.find(teachOverlayPattern, pos10)
    if m.isNone: break
    let bounds = m.get().matchBounds
    let before = result[max(0, bounds.a - 80) ..< bounds.a]
    if "workArea" in before:
      let old = m.get().match
      var newStr = old.replace("transparent:!0", "transparent:!globalThis.__isVM")
      newStr = newStr.replace("backgroundColor:\"#00000000\"", "backgroundColor:globalThis.__isVM?\"#000000\":\"#00000000\"")
      result = result.replace(old, newStr)
      echo "  [OK] teach overlay: VM-aware transparency (transparent on native, dark backdrop on VMs)"
      changes += 1
      inc patchesApplied
      found10 = true
      break
    pos10 = bounds.b + 1
  if not found10:
    echo "  [FAIL] teach overlay transparency pattern not found"

  # Patch 10b: Force teach overlay display to primary monitor on Linux
  let xlrPattern = re"(function [\w$]+\(([\w$]+)\)\{)(return \2===null\?[\w$]+\.screen\.getPrimaryDisplay\(\):[\w$]+\.screen\.getAllDisplays\(\)\.find)"
  var count10b = 0
  result = result.replace(xlrPattern, proc(m: RegexMatch): string =
    inc count10b
    if count10b > 1: return m.match
    let param = m.captures[1]
    m.captures[0] & "if(process.platform===\"linux\")" & param & "=null;" & m.captures[2]
  )
  if count10b >= 1:
    echo &"  [OK] teach overlay display: forced to primary monitor on Linux ({count10b} match)"
    changes += count10b
    inc patchesApplied
  else:
    echo "  [FAIL] xlr display resolver pattern: 0 matches"

  # Patch 11: Force mVt() isEnabled to return true on Linux
  let mVtPattern = re"(function [\w$]+\(\)\{)return [\w$]+\([\w$]+\)\?[\w$]+\.has\(process\.platform\)&&[\w$]+\(\):[\w$]+\(\)\}"
  var count11 = 0
  result = result.replace(mVtPattern, proc(m: RegexMatch): string =
    inc count11
    if count11 > 1: return m.match
    m.captures[0] & "if(process.platform===\"linux\")return!0;" &
      m.match[m.captures[0].len .. ^1]
  )
  if count11 >= 1:
    echo &"  [OK] mVt isEnabled: force true on Linux ({count11} match)"
    changes += count11
    inc patchesApplied
  else:
    echo "  [FAIL] mVt isEnabled pattern: 0 matches"

  # Patch 12: Force rj() to return true on Linux
  let rjPattern = re"""(function [\w$]+\(\)\{)return [\w$]+\.has\(process\.platform\)\?[\w$]+\(\)&&[\w$]+\("chicagoEnabled"\):!1\}"""
  var count12 = 0
  result = result.replace(rjPattern, proc(m: RegexMatch): string =
    inc count12
    if count12 > 1: return m.match
    m.captures[0] & "if(process.platform===\"linux\")return!0;" &
      m.match[m.captures[0].len .. ^1]
  )
  if count12 >= 1:
    echo &"  [OK] rj chicagoEnabled bypass: force true on Linux ({count12} match)"
    changes += count12
    inc patchesApplied
  else:
    echo "  [FAIL] rj pattern: 0 matches"

  # -- Patch 13: Linux-aware computer-use tool descriptions --
  echo "  --- Tool description patches (non-fatal) ---"
  var descChanges = 0

  # 13a: Lf allowlist gate warning -- empty on Linux
  let lfPat = re("([\\w$]+)=\"The frontmost application must be in the session allowlist at the time of this call, or this tool returns an error and does nothing\\.\"")
  var countLf = 0
  result = result.replace(lfPat, proc(m: RegexMatch): string =
    inc countLf
    if countLf > 1: return m.match
    let v = m.captures[0]
    v & "=process.platform===\"linux\"?\"\":\"The frontmost application must be in the session allowlist at the time of this call, or this tool returns an error and does nothing.\""
  )
  if countLf >= 1:
    echo "  [OK] 13a Lf allowlist gate: empty on Linux"
    inc descChanges
    inc patchesApplied
  else:
    echo "  [FAIL] 13a Lf: not found"

  # 13b: request_access -- "Linux" instead of "macOS"/"Finder"
  let old13b = "'This computer is running macOS. The file manager is \"Finder\". '"
  let new13b = "(e.platform===\"linux\"?" &
    "'This computer is running Linux. " &
    "On Linux, ALL applications are automatically accessible at full " &
    "tier without explicit permission grants. You do NOT need to call " &
    "request_access before using other tools. If called, it returns " &
    "synthetic grant confirmations. The file manager depends on the " &
    "desktop environment (e.g. Nautilus on GNOME, Dolphin on KDE, " &
    "Thunar on XFCE). '" &
    ":" &
    "'This computer is running macOS. The file manager is \"Finder\". ')"
  if old13b in result:
    result = result.replace(old13b, new13b)
    echo "  [OK] 13b request_access: Linux platform prefix"
    inc descChanges
    inc patchesApplied
  else:
    echo "  [FAIL] 13b request_access macOS prefix: not found"

  # 13c: App identifier (request_access apps schema)
  let old13c = "'Application display names (e.g. \"Slack\", \"Calendar\") or bundle identifiers (e.g. \"com.tinyspeck.slackmacgap\"). Display names are resolved case-insensitively against installed apps.'"
  let new13c = "(e.platform===\"linux\"?" &
    "'Application names as shown in window titles, or WM_CLASS values " &
    "(e.g. \"firefox\", \"org.gnome.Nautilus\"). " &
    "On Linux all apps are auto-granted at full tier.'" &
    ":" &
    "'Application display names (e.g. \"Slack\", \"Calendar\") or bundle " &
    "identifiers (e.g. \"com.tinyspeck.slackmacgap\"). Display names are " &
    "resolved case-insensitively against installed apps.')"
  if old13c in result:
    result = result.replace(old13c, new13c)
    echo "  [OK] 13c request_access apps: Linux identifiers"
    inc descChanges
    inc patchesApplied
  else:
    echo "  [FAIL] 13c request_access apps: not found"

  # 13d: open_application app identifier
  let old13d = "'Display name (e.g. \"Slack\") or bundle identifier (e.g. \"com.tinyspeck.slackmacgap\").'"
  let new13d = "(e.platform===\"linux\"?" &
    "'Application name or WM_CLASS (e.g. \"firefox\", \"nautilus\").'" &
    ":" &
    "'Display name (e.g. \"Slack\") or bundle identifier (e.g. \"com.tinyspeck.slackmacgap\").')"
  if old13d in result:
    result = result.replace(old13d, new13d)
    echo "  [OK] 13d open_application app: Linux identifiers"
    inc descChanges
    inc patchesApplied
  else:
    echo "  [FAIL] 13d open_application app: not found"

  # 13e: open_application -- no allowlist on Linux
  let old13e = "\"Bring an application to the front, launching it if necessary. The target application must already be in the session allowlist \xe2\x80\x94 call request_access first.\""
  let new13e = "(process.platform===\"linux\"?" &
    "\"Bring an application to the front, launching it if necessary. " &
    "On Linux, all applications are directly accessible.\"" &
    ":" &
    "\"Bring an application to the front, launching it if necessary. " &
    "The target application must already be in the session allowlist " &
    "\xe2\x80\x94 call request_access first.\")"
  if old13e in result:
    result = result.replace(old13e, new13e)
    echo "  [OK] 13e open_application: no allowlist on Linux"
    inc descChanges
    inc patchesApplied
  else:
    echo "  [FAIL] 13e open_application: not found"

  # 13f: screenshot (none-filtering)
  let old13f = "\"Take a screenshot of the primary display. On this platform, " &
    "screenshots are NOT filtered \xe2\x80\x94 all open windows are visible. " &
    "Input actions targeting apps not in the session allowlist are rejected.\""
  let new13f = "(process.platform===\"linux\"?" &
    "\"Take a screenshot of the primary display. " &
    "All open windows are visible.\"" &
    ":" &
    "\"Take a screenshot of the primary display. On this platform, " &
    "screenshots are NOT filtered \xe2\x80\x94 all open windows are visible. " &
    "Input actions targeting apps not in the session allowlist are rejected.\")"
  if old13f in result:
    result = result.replace(old13f, new13f)
    echo "  [OK] 13f screenshot: clean description on Linux"
    inc descChanges
    inc patchesApplied
  else:
    echo "  [FAIL] 13f screenshot: not found"

  # 13g: screenshot suffix
  let ssSfxPat = re("([\\w$]+)\\+\" Returns an error if the allowlist is empty\\. The returned image is what subsequent click coordinates are relative to\\.\"")
  var countSfx = 0
  result = result.replace(ssSfxPat, proc(m: RegexMatch): string =
    inc countSfx
    if countSfx > 1: return m.match
    let v = m.captures[0]
    v & "+(process.platform===\"linux\"" &
      "?\" The returned image is what subsequent click coordinates are relative to.\"" &
      ":\" Returns an error if the allowlist is empty. The returned image is what subsequent click coordinates are relative to.\")"
  )
  if countSfx >= 1:
    echo "  [OK] 13g screenshot suffix: no allowlist error on Linux"
    inc descChanges
    inc patchesApplied
  else:
    echo "  [FAIL] 13g screenshot suffix: not found"

  if descChanges > 0:
    changes += descChanges
    echo &"  [OK] {descChanges}/7 description patches applied"
  else:
    echo "  [FAIL] No description patches applied (descriptions unchanged)"

  # -- Sub-patch 14: Linux-aware CU system prompt --

  # 14a: Replace "Separate filesystems" paragraph (2 occurrences)
  # Uses UTF-8 em-dash: \xe2\x80\x94
  let sepOldFull = "**Separate filesystems.** Computer-use actions (clicks, typing, clipboard writes) happen on the user\x27s real computer \xe2\x80\x94 a different system from your sandbox. "
  let sepCount = result.count(sepOldFull)
  if sepCount >= 2:
    let sepNewFull = "${process.platform===\"linux\"" &
      "?\"**Same filesystem.** Computer-use actions and your CLI tools operate on the same Linux machine. " &
      "There is no sandbox \\u2014 files you create are directly accessible to desktop applications and vice versa. \"" &
      ":\"**Separate filesystems.** Computer-use actions (clicks, typing, clipboard writes) " &
      "happen on the user\x27s real computer \xe2\x80\x94 a different system from your sandbox. \"}"
    result = result.replace(sepOldFull, sepNewFull)
    echo &"  [OK] 14a separate filesystems: replaced {sepCount} occurrences with Linux-aware text"
    changes += sepCount
    inc patchesApplied
  else:
    echo &"  [FAIL] 14a separate filesystems: expected 2 occurrences, found {sepCount}"

  # 14b: Replace macOS app names with generic Linux terms
  let appsOld = "Maps, Notes, Finder, Photos, System Settings"
  let appsNew = "${process.platform===\"linux\"?\"the file manager, image viewer, terminal emulator, system settings\":\"Maps, Notes, Finder, Photos, System Settings\"}"
  if appsOld in result:
    result = result.replace(appsOld, appsNew)
    echo "  [OK] 14b app names: replaced macOS apps with Linux-generic terms"
    changes += 1
    inc patchesApplied
  else:
    echo "  [FAIL] 14b app names: not found"

  # 14c: File manager name
  let fmOld = "\"File Explorer\":\"Finder\""
  let fmNew = "\"File Explorer\":process.platform===\"linux\"?\"Files\":\"Finder\""
  if fmOld in result:
    result = result.replace(fmOld, fmNew)
    echo "  [OK] 14c file manager name: added Linux branch"
    changes += 1
    inc patchesApplied
  else:
    echo "  [FAIL] 14c file manager name: pattern not found"

  # Final check
  if patchesApplied < EXPECTED_PATCHES:
    echo &"  [FAIL] Only {patchesApplied}/{EXPECTED_PATCHES} patches applied -- check [FAIL] messages above"
    # Still write partial changes so the build can be inspected
    quit(1)

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
