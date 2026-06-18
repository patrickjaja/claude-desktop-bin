# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
# Enable Chrome browser tools ("Claude in Chrome") on Linux.
# Five patches:
#   A - Binary path resolution (native host executable)
#   B - NativeMessagingHosts directory paths
#   C - Chrome user data directory detection (extension/profile discovery)
#   D - Chrome extension auto-install (External Extensions pref)
#   E - Chrome DevTools opener (chrome://inspect via xdg-open)

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
  var patchesApplied = 0

  # Patch A: Binary path resolution
  # Upstream (v1.14271.0) refactored the native-host path fn from the old
  # darwin/win32/"Helpers" branch into a flat ternary:
  #   function pyt(){const A=`${Byt}.exe`;return sA.app.isPackaged?
  #     AA.join(process.resourcesPath,A):AA.join(sA.app.getAppPath(),".../chrome-native-host/artifacts",A)}
  # We inject a Linux short-circuit at the start of the function body that
  # returns the Claude Code native host installed under ~/.claude.
  let alreadyA =
    re2"""if\(process\.platform==="linux"\)return require\("path"\)\.join\(require\("os"\)\.homedir\(\),"\.claude","chrome","chrome-native-host"\)"""
  var alreadyAFound = false
  for m in result.findAll(alreadyA):
    alreadyAFound = true
    break

  if alreadyAFound:
    echo "  [OK] Binary path resolution: already patched (skipped)"
    patchesApplied += 1
  else:
    # Capture: function NAME(){const VAR=`${VAR2}.exe`;return ELECTRON.app.isPackaged?
    let patternA =
      re2"""(function [\w$]+\(\)\{)(const [\w$]+=`\$\{[\w$]+\}\.exe`;return [\w$]+\.app\.isPackaged\?)"""

    let linuxBinary =
      "if(process.platform===\"linux\")return require(\"path\").join(require(\"os\").homedir(),\".claude\",\"chrome\",\"chrome-native-host\");"

    var countA = result.replaceFirst(
      patternA,
      proc(m: RegexMatch2, s: string): string =
        s[m.group(0)] & linuxBinary & s[m.group(1)],
    )
    if countA >= 1:
      echo &"  [OK] Binary path resolution: redirected to Claude Code native host ({countA} match)"
      patchesApplied += 1
    else:
      echo "  [FAIL] Binary path resolution: pattern not found"
      echo "         Debug: rg -o 'chrome-native-host/artifacts' index.js"

  # Patch B: NativeMessagingHosts manifest installation (Linux)
  #
  # Upstream (v1.14271.0) refactored native-host registration. Previously a
  # per-browser dir enumerator (Aoe) returned a list and an install LOOP (xkn)
  # wrote the manifest to every entry, so adding Linux dirs to the enumerator
  # was enough. That loop is GONE. Now:
  #   - myt() returns a single {name:"All",path: userData/ChromeNativeHost} on ALL platforms
  #   - the per-browser enumerator (zcr) returns [] and is only used by the
  #     UNINSTALL path (Bpn)
  #   - the installer dpn() writes the manifest to myt()[0].path only, via Cpn()
  # Chrome/Chromium on Linux read native messaging host manifests from
  # ~/.config/<browser>/NativeMessagingHosts/, NOT from Electron's userData,
  # so upstream's single-dir write does not make the host discoverable on Linux.
  #
  # Fix: inject a Linux short-circuit at the START of the installer dpn() that
  # writes the manifest to every real Linux browser NativeMessagingHosts dir,
  # reusing the existing Cpn(dir,"All") helper (which mkdir -p's and writes the
  # JSON manifest), then returns before the Windows-registry logic.
  let alreadyB = re2"""\[browser-tools\] diagnostics: native host manifest installed="""
  var alreadyBFound = false
  for m in result.findAll(alreadyB):
    alreadyBFound = true
    break

  if alreadyBFound:
    echo "  [OK] NativeMessagingHosts paths: already patched (skipped)"
    patchesApplied += 1
  else:
    # Capture the installer head and the name of the Cpn-style manifest writer.
    #   async function dpn(){var n,o,s;const A=(n=myt()[0])==null?void 0:n.path;if(!A)return;
    #   ...if([...].some(Boolean))try{await Cpn(A,"All")}...
    # group(1) = installer head up to "if(!A)return;"
    # The regex engine caps {0,N} at N<=100, so the variable middle (~114 chars
    # between "if(!A)return;" and "try{await") is matched with two bounded atoms.
    let patternB =
      re2"""(async function [\w$]+\(\)\{var [\w$]+,[\w$]+,[\w$]+;const A=\([\w$]+=[\w$]+\(\)\[0\]\)==null\?void 0:[\w$]+\.path;if\(!A\)return;)(.{0,99}.{0,40}?try\{await )([\w$]+)(\(A,"All"\))"""

    var countB = result.replaceFirst(
      patternB,
      proc(m: RegexMatch2, s: string): string =
        let head = s[m.group(0)]
        let writerFn = s[m.group(2)]
        let linuxInstall =
          "if(process.platform===\"linux\"){" &
          "const _h=require(\"os\").homedir(),_p=require(\"path\"),_fs=require(\"fs\");" &
          "const _rel=[" & "[\"Chrome\",[\".config\",\"google-chrome\"]]," &
          "[\"Chromium\",[\".config\",\"chromium\"]]," &
          "[\"Brave\",[\".config\",\"BraveSoftware\",\"Brave-Browser\"]]," &
          "[\"Edge\",[\".config\",\"microsoft-edge\"]]," &
          "[\"Vivaldi\",[\".config\",\"vivaldi\"]]," &
          "[\"Opera\",[\".config\",\"opera\"]]" &
          "];let _any=!1,_det=[];for(const[_n,_seg]of _rel){const _base=_p.join(_h,..._seg);" &
          "try{if(_fs.existsSync(_base)){await " & writerFn &
          "(_p.join(_base,\"NativeMessagingHosts\"),\"All\");_any=!0;_det.push(_n)}}catch(_e){}}" &
          "console.log(\"[browser-tools] diagnostics: native host manifest installed=\"+_any+\" browsers=[\"+_det.join(\", \")+\"]\");" &
          "return}"
        # Keep the original installer body intact after our Linux short-circuit.
        head & linuxInstall & s[m.group(1)] & writerFn & s[m.group(3)],
    )
    if countB >= 1:
      echo &"  [OK] NativeMessagingHosts paths: added Linux manifest install loop (6 browsers, {countB} match)"
      patchesApplied += 1
    else:
      echo "  [FAIL] NativeMessagingHosts paths: pattern not found"
      echo "         Debug: rg -o '\"ChromeNativeHost\".{0,30}' index.js"

  # Patch C: Chrome user data directory detection (WXA)
  # Upstream (v1.14271.0) collapsed the old darwin/win32/[] branching fn (Xne)
  # into a Windows-only fn (WXA) that UNCONDITIONALLY returns AppData\Local paths
  # (no process.platform check, no Linux [] fallthrough):
  #   function WXA(){const A=ti.homedir();{const e=AA.join(A,"AppData","Local");
  #     return[{name:"Chrome",path:...},{name:"Edge",path:...}]}}
  # On Linux this hands back non-existent Windows paths, breaking profile/extension
  # discovery (consumers: jcr/Wcr/hyt/fyt). Inject a Linux branch at the start of
  # the function body returning the real ~/.config/<browser> user-data dirs.
  let alreadyC =
    re2"""if\(process\.platform==="linux"\)return\[\{name:"Chrome",path:require\("path"\)\.join\([\w$]+,"\.config","google-chrome"\)\}"""
  var alreadyCFound = false
  for m in result.findAll(alreadyC):
    alreadyCFound = true
    break

  if alreadyCFound:
    echo "  [OK] Chrome user data dirs: already patched (skipped)"
    patchesApplied += 1
  else:
    # Capture: function NAME(){const VAR=HOMEDIR.homedir();   (group2 = homedir var)
    let patternC =
      re2"""(function [\w$]+\(\)\{const )([\w$]+)(=[\w$]+\.homedir\(\);)(\{const [\w$]+=[\w$]+\.join\([\w$]+,"AppData","Local"\);return\[)"""

    var countC = result.replaceFirst(
      patternC,
      proc(m: RegexMatch2, s: string): string =
        let homeVar = s[m.group(1)]
        let linuxUserDataDirs =
          "if(process.platform===\"linux\")return[" &
          "{name:\"Chrome\",path:require(\"path\").join(" & homeVar &
          ",\".config\",\"google-chrome\")}," &
          "{name:\"Chromium\",path:require(\"path\").join(" & homeVar &
          ",\".config\",\"chromium\")}," & "{name:\"Brave\",path:require(\"path\").join(" &
          homeVar & ",\".config\",\"BraveSoftware\",\"Brave-Browser\")}," &
          "{name:\"Vivaldi\",path:require(\"path\").join(" & homeVar &
          ",\".config\",\"vivaldi\")}," & "{name:\"Opera\",path:require(\"path\").join(" &
          homeVar & ",\".config\",\"opera\")}" & "];"
        # group0 = "function NAME(){const ", g1 = homevar, g2 = "=...homedir();", g3 = rest
        s[m.group(0)] & homeVar & s[m.group(2)] & linuxUserDataDirs & s[m.group(3)],
    )
    if countC >= 1:
      echo &"  [OK] Chrome user data dirs: added 5 Linux browsers ({countC} match)"
      patchesApplied += 1
    else:
      echo "  [FAIL] Chrome user data dirs: pattern not found"
      echo "         Debug: rg -o '\"User Data\".{{0,30}}' index.js"

  # Patch D: Chrome extension auto-install (vkr)
  # The vkr function returns an error on non-darwin. On Linux, the Chrome External Extensions
  # directory is at ~/.config/google-chrome/External Extensions/ (and chromium equivalent).
  # Patch: allow linux through the guard, inject Linux-specific install path.
  let alreadyD =
    re2"""process\.platform!=="darwin"&&process\.platform!=="linux"\)return\{status:"""
  var alreadyDFound = false
  for m in result.findAll(alreadyD):
    alreadyDFound = true
    break

  if alreadyDFound:
    echo "  [OK] Chrome extension install: already patched (skipped)"
    patchesApplied += 1
  else:
    # Match the guard clause: if(process.platform!=="darwin")return{status:<enum>.Error,error:`Unsupported platform...`}
    # We need to capture the status enum variable name and the full guard
    let patternD =
      re2"""(if\(process\.platform!=="darwin"\)return\{status:)([\w$]+)(\.Error,error:`Unsupported platform: \$\{process\.platform\}\. Only macOS is supported\.`\})"""

    var countD = result.replaceFirst(
      patternD,
      proc(m: RegexMatch2, s: string): string =
        let enumVar = s[m.group(1)]
        # New guard: reject platforms that are neither darwin nor linux
        "if(process.platform!==\"darwin\"&&process.platform!==\"linux\")return{status:" &
          enumVar &
          ".Error,error:`Unsupported platform: ${process.platform}. Only macOS and Linux are supported.`};" &
          # Linux-specific code path (runs and returns before darwin code)
          "if(process.platform===\"linux\"){" &
          "try{const _h=require(\"os\").homedir(),_p=require(\"path\")," &
          "_id=\"fcoeoabgfenejglbffodgkkbkcdhcgfn\"," &
          "_url=\"https://clients2.google.com/service/update2/crx\"," &
          "_dirs=[_p.join(_h,\".config\",\"google-chrome\"),_p.join(_h,\".config\",\"chromium\")];" &
          "let _ok=!1;for(const _d of _dirs){try{const _e=_p.join(_d,\"External Extensions\");" &
          "require(\"fs\").mkdirSync(_e,{recursive:!0});" &
          "require(\"fs\").writeFileSync(_p.join(_e,_id+\".json\")," &
          "JSON.stringify({external_update_url:_url},null,2),\"utf-8\");" &
          "console.log(\"[Chrome Extension Install] Wrote to \"+_e);_ok=!0}catch(_x){}}" &
          "return _ok?{status:" & enumVar & ".Succeeded}:{status:" & enumVar &
          ".Error,error:\"No Chrome/Chromium config dirs found on Linux\"}}" &
          "catch(e){return{status:" & enumVar &
          ".Error,error:e instanceof Error?e.message:\"Unknown error\"}}}",
    )
    if countD >= 1:
      echo &"  [OK] Chrome extension install: added Linux support ({countD} match)"
      patchesApplied += 1
    else:
      echo "  [FAIL] Chrome extension install: pattern not found"
      echo "         Debug: rg -o 'Only macOS is supported.{{0,20}}' index.js"

  # Patch E: Chrome DevTools opening (YOr)
  # The YOr function opens chrome://inspect on darwin/win32 but has no Linux handler.
  # On Linux, use xdg-open which works across all desktop environments.
  let alreadyE =
    re2"""process\.platform==="linux"&&await [\w$]+\("xdg-open",\["chrome://inspect"\]\)"""
  var alreadyEFound = false
  for m in result.findAll(alreadyE):
    alreadyEFound = true
    break

  if alreadyEFound:
    echo "  [OK] Chrome DevTools opener: already patched (skipped)"
    patchesApplied += 1
  else:
    # Match: process.platform==="win32"&&await <execFn>("start",["chrome","chrome://inspect"])
    # Replace with: adding a linux handler after the win32 one
    let patternE =
      re2"""(process\.platform==="win32"&&await )([\w$]+)(\("start",\["chrome","chrome://inspect"\]\))"""

    var countE = result.replaceFirst(
      patternE,
      proc(m: RegexMatch2, s: string): string =
        let execFn = s[m.group(1)]
        # Change win32's && to ? so we can chain :linux&&... as the false branch
        "process.platform===\"win32\"?await " & execFn & s[m.group(2)] &
          ":process.platform===\"linux\"&&await " & execFn &
          "(\"xdg-open\",[\"chrome://inspect\"])",
    )
    if countE >= 1:
      echo &"  [OK] Chrome DevTools opener: added Linux xdg-open handler ({countE} match)"
      patchesApplied += 1
    else:
      echo "  [FAIL] Chrome DevTools opener: pattern not found"
      echo "         Debug: rg -o 'chrome://inspect.{{0,30}}' index.js"

  if patchesApplied < EXPECTED_PATCHES:
    raise newException(
      ValueError,
      &"fix_browser_tools_linux: Only {patchesApplied}/{EXPECTED_PATCHES} patches applied",
    )

  # Verify brace balance
  let originalDelta = input.count('{') - input.count('}')
  let patchedDelta = result.count('{') - result.count('}')
  if originalDelta != patchedDelta:
    let diff = patchedDelta - originalDelta
    raise newException(
      ValueError,
      &"fix_browser_tools_linux: Patch introduced brace imbalance: {diff:+} unmatched braces",
    )

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_browser_tools_linux <file>"
    quit(1)
  let file = paramStr(1)
  echo "=== Patch: fix_browser_tools_linux ==="
  echo &"  Target: {file}"
  if not fileExists(file):
    echo &"  [FAIL] File not found: {file}"
    quit(1)
  let input = readFile(file)
  let output = apply(input)
  if output == input:
    echo &"  [OK] All patches already applied (no changes needed)"
  else:
    writeFile(file, output)
    echo &"  [PASS] Patches applied"
