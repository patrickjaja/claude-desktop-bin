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

  # Patch 1: getHostPlatform() - Add Linux support
  # Uses backreference \2 in pattern to match same arch var
  let platformPattern =
    re"""(getHostPlatform\(\)\{const (\w+)=process\.arch;if\(process\.platform==="darwin"\)return \2==="arm64"\?"darwin-arm64":"darwin-x64";if\(process\.platform==="win32"\)return)(.+?)(;throw new Error\()"""

  let m1 = result.find(platformPattern)
  if m1.isSome:
    let m = m1.get
    let archVar = m.captures[1]
    let win32Return = m.captures[2]
    let linuxCheck =
      "if(process.platform===\"linux\")return " & archVar &
      "===\"arm64\"?\"linux-arm64\":\"linux-x64\";"
    let replacement =
      m.captures[0] & win32Return & ";" & linuxCheck & "throw new Error("
    result =
      result[0 ..< m.matchBounds.a] & replacement & result[m.matchBounds.b + 1 .. ^1]
    echo "  [OK] getHostPlatform(): 1 match(es)"
  elif "getHostPlatform(){" in result and
      "if(process.platform===\"linux\")return" in result and "\"linux-x64\"" in result:
    echo "  [OK] getHostPlatform(): already patched"
  else:
    echo "  [FAIL] getHostPlatform(): 0 matches, expected >= 1"
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
  # Uses backreference \1 and \2
  let statusPattern =
    re"""async getStatus\(\)\{if\(await this\.getLocalBinaryPath\(\)\)return ([\w$]+)\.Ready;const (\w+)=this\.getHostTarget\(\);if\(this\.preparingPromise\)return \1\.Updating;if\(await this\.binaryExistsForTarget\(\2,this\.requiredVersion\)\)"""

  let m3 = result.find(statusPattern)
  if m3.isSome:
    let m = m3.get
    let enumName = m.captures[0]
    let varName = m.captures[1]
    let replacement =
      "async getStatus(){if(process.platform===\"linux\"){try{const fs=require(\"fs\");" &
      "for(const p of[\"/usr/bin/claude\",(process.env.HOME||\"\")+\"/.local/bin/claude\",\"/usr/local/bin/claude\"])" &
      "if(fs.existsSync(p))return " & enumName & ".Ready;" &
      "try{require(\"child_process\").execSync(\"which claude\",{encoding:\"utf-8\"});return " &
      enumName & ".Ready}catch(e2){}" & "return " & enumName &
      ".NotInstalled}catch(err){return " & enumName & ".NotInstalled}}" &
      "if(await this.getLocalBinaryPath())return " & enumName & ".Ready;const " & varName &
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
