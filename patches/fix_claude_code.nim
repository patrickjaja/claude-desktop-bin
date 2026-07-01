# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
# Patch Claude Desktop to use system-installed Claude Code on Linux.
# Three patches: getHostPlatform, getBinaryPathIfReady, getStatus.
# Uses std/nre for backreference support in patterns.

import std/[os, strformat, strutils, options]
import std/nre

proc apply*(input: string): string =
  result = input
  var failed = false

  # Patch 1: getHostPlatform() Linux support — now a REGRESSION GUARD.
  #
  # The Windows MSIX's getHostPlatform() only handled darwin/win32 and threw on
  # Linux, so we injected a linux branch. The official Linux .deb UPSTREAMED it:
  # v1.17377 natively ships
  #   getHostPlatform(){const e=process.arch;
  #     if(process.platform==="darwin")return e==="arm64"?"darwin-arm64":"darwin-x64";
  #     if(process.platform==="win32")return e==="arm64"?"win32-arm64":"win32-x64";
  #     if(process.platform==="linux")return e==="arm64"?"linux-arm64":"linux-x64";
  #     throw new Error(`Unsupported platform: ...
  # Re-injecting a linux branch now would append a SECOND, dead one (the old
  # find-pattern's `.+?` even swallowed the native branch). So per CLAUDE.md Rule 6
  # we assert the native Linux branch is PRESENT and fail loud if a future bump
  # ever removes it (which would break Claude Code's platform resolution on Linux).
  let nativeLinuxHostPlatform =
    re"""getHostPlatform\(\)\{const (\w+)=process\.arch;.*?if\(process\.platform==="linux"\)return \1==="arm64"\?"linux-arm64":"linux-x64""""
  if result.find(nativeLinuxHostPlatform).isSome:
    echo "  [OK] getHostPlatform(): native Linux branch present (linux-arm64/linux-x64) — regression guard satisfied"
  else:
    echo "  [FAIL] getHostPlatform(): native Linux branch NOT found — upstream may have dropped Linux support; re-audit Patch 1"
    failed = true

  # Patch 2: getBinaryPathIfReady() - Find claude binary on Linux
  let binaryPattern =
    re"""(async getBinaryPathIfReady\(\)\{)(?!if\(process\.platform==="linux"\))"""

  let linuxBinaryCheck =
    "if(process.platform===\"linux\"){try{const fs=require(\"fs\");" &
    "for(const p of[\"/usr/bin/claude\"," &
    "(process.env.HOME||\"\")+\"/.local/bin/claude\"," & "\"/usr/local/bin/claude\"])" &
    "if(fs.existsSync(p)){console.log(\"[claude-code] binary: found at \"+p);return p}" &
    "const wp=require(\"child_process\").execSync(\"which claude\",{encoding:\"utf-8\"}).trim();" &
    "console.log(\"[claude-code] binary: found via which at \"+wp);return wp}" &
    "catch(err){console.warn(\"[claude-code] binary: NOT FOUND - install claude-code CLI (npm i -g @anthropic-ai/claude-code)\")}}"

  let m2 = result.find(binaryPattern)
  if m2.isSome:
    let m = m2.get
    let replacement = m.captures[0] & linuxBinaryCheck
    result =
      result[0 ..< m.matchBounds.a] & replacement & result[m.matchBounds.b + 1 .. ^1]
    echo "  [OK] getBinaryPathIfReady(): 1 match(es)"
  elif "async getBinaryPathIfReady(){if(process.platform===\"linux\")" in result:
    echo "  [OK] getBinaryPathIfReady(): already patched"
  else:
    echo "  [FAIL] getBinaryPathIfReady(): 0 matches, expected >= 1"
    failed = true

  # Patch 3: getStatus() - Return Ready if system binary exists on Linux
  # Uses backreference \1 and \3
  # Note: upstream may add extra checks to the first if-condition
  # (e.g. `||await this.getHostPreseedInPlacePath()`), so capture the whole
  # condition body between `if(` and `)return X.Ready`.
  let statusPattern =
    re"""async getStatus\(\)\{if\((await this\.getLocalBinaryPath\(\)(?:\|\|await this\.\w+\(\))*)\)return ([\w$]+)\.Ready;const (\w+)=this\.getHostTarget\(\);if\(this\.preparingPromise\)return \2\.Updating;if\(await this\.binaryExistsForTarget\(\3,this\.requiredVersion\)\)"""

  let m3 = result.find(statusPattern)
  if m3.isSome:
    let m = m3.get
    let origCond = m.captures[0]
    let enumName = m.captures[1]
    let varName = m.captures[2]
    let replacement =
      "async getStatus(){if(process.platform===\"linux\"){try{const fs=require(\"fs\");" &
      "for(const p of[\"/usr/bin/claude\",(process.env.HOME||\"\")+\"/.local/bin/claude\",\"/usr/local/bin/claude\"])" &
      "if(fs.existsSync(p))return " & enumName & ".Ready;" &
      "try{require(\"child_process\").execSync(\"which claude\",{encoding:\"utf-8\"});return " &
      enumName & ".Ready}catch(e2){}" & "return " & enumName &
      ".NotInstalled}catch(err){return " & enumName & ".NotInstalled}}" & "if(" &
      origCond & ")return " & enumName & ".Ready;const " & varName &
      "=this.getHostTarget();if(this.preparingPromise)return " & enumName &
      ".Updating;if(await this.binaryExistsForTarget(" & varName &
      ",this.requiredVersion))"
    result =
      result[0 ..< m.matchBounds.a] & replacement & result[m.matchBounds.b + 1 .. ^1]
    echo "  [OK] getStatus(): 1 match(es)"
  elif "async getStatus(){if(process.platform===\"linux\")" in result:
    echo "  [OK] getStatus(): already patched"
  else:
    echo "  [FAIL] getStatus(): 0 matches, expected >= 1"
    failed = true

  if failed:
    raise newException(ValueError, "fix_claude_code: Some patterns did not match")

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_claude_code <file>"
    quit(1)
  let file = paramStr(1)
  echo "=== Patch: fix_claude_code ==="
  echo &"  Target: {file}"
  if not fileExists(file):
    echo &"  [FAIL] File not found: {file}"
    quit(1)
  let input = readFile(file)
  let output = apply(input)
  if output != input:
    writeFile(file, output)
    echo "  [PASS] All patterns matched and applied"
  else:
    echo "  [WARN] No changes made (patterns may have already been applied)"
