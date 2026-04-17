# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
# Nim port of fix_claude_code.py
# Uses std/nre because status_pattern has a \1 backreference in the pattern.

import std/[os, strformat, strutils, options]
import std/nre

proc apply*(input: string): string =
  var content = input
  let original = input
  var failed = false

  # Patch 1: getHostPlatform() — add Linux support
  let platformPattern = re"""(getHostPlatform\(\)\{const (\w+)=process\.arch;if\(process\.platform==="darwin"\)return \2==="arm64"\?"darwin-arm64":"darwin-x64";if\(process\.platform==="win32"\)return)(.+?)(;throw new Error\()"""
  var m1 = content.find(platformPattern)
  var count1 = 0
  if m1.isSome:
    let mm = m1.get
    let g1 = mm.captures[0]
    let archVar = mm.captures[1]
    let winReturn = mm.captures[2]
    let g4 = mm.captures[3]
    let linuxCheck = "if(process.platform===\"linux\")return " & archVar & "===\"arm64\"?\"linux-arm64\":\"linux-x64\";"
    let replacement = g1 & winReturn & ";" & linuxCheck & "throw new Error("
    let s = mm.matchBounds
    content = content[0 ..< s.a] & replacement & content[s.b + 1 .. ^1]
    count1 = 1
  if count1 >= 1:
    echo &"  [OK] getHostPlatform(): {count1} match(es)"
  elif content.contains("getHostPlatform(){") and
       content.contains("if(process.platform===\"linux\")return") and
       content.contains("\"linux-x64\""):
    echo "  [OK] getHostPlatform(): already patched"
  else:
    echo "  [FAIL] getHostPlatform(): 0 matches, expected >= 1"
    failed = true

  # Patch 2: getBinaryPathIfReady() — find claude binary on Linux
  const LINUX_BINARY_CHECK =
    "if(process.platform===\"linux\"){try{const fs=require(\"fs\");" &
    "for(const p of[\"/usr/bin/claude\"," &
    "(process.env.HOME||\"\")+\"/.local/bin/claude\"," &
    "\"/usr/local/bin/claude\"])" &
    "if(fs.existsSync(p)){console.log(\"[claude-code] binary: found at \"+p);return p}" &
    "const wp=require(\"child_process\").execSync(\"which claude\",{encoding:\"utf-8\"}).trim();" &
    "console.log(\"[claude-code] binary: found via which at \"+wp);return wp}" &
    "catch(err){console.warn(\"[claude-code] binary: NOT FOUND - install claude-code CLI (npm i -g @anthropic-ai/claude-code)\")}}"

  let binaryPattern = re"""(async getBinaryPathIfReady\(\)\{)(?!if\(process\.platform==="linux"\))"""
  var count2 = 0
  var m2 = content.find(binaryPattern)
  if m2.isSome:
    let mm = m2.get
    let g1 = mm.captures[0]
    let replacement = g1 & LINUX_BINARY_CHECK
    let s = mm.matchBounds
    content = content[0 ..< s.a] & replacement & content[s.b + 1 .. ^1]
    count2 = 1
  if count2 >= 1:
    echo &"  [OK] getBinaryPathIfReady(): {count2} match(es)"
  elif content.contains("async getBinaryPathIfReady(){if(process.platform===\"linux\")"):
    echo "  [OK] getBinaryPathIfReady(): already patched"
  else:
    echo "  [FAIL] getBinaryPathIfReady(): 0 matches, expected >= 1"
    failed = true

  # Patch 3: getStatus()
  let statusPattern = re"""async getStatus\(\)\{if\(await this\.getLocalBinaryPath\(\)\)return ([\w$]+)\.Ready;const (\w+)=this\.getHostTarget\(\);if\(this\.preparingPromise\)return \1\.Updating;if\(await this\.binaryExistsForTarget\(\2,this\.requiredVersion\)\)"""
  var count3 = 0
  var m3 = content.find(statusPattern)
  if m3.isSome:
    let mm = m3.get
    let enumName = mm.captures[0]
    let varName = mm.captures[1]
    let replacement =
      "async getStatus(){if(process.platform===\"linux\"){try{const fs=require(\"fs\");" &
      "for(const p of[\"/usr/bin/claude\",(process.env.HOME||\"\")+\"/.local/bin/claude\",\"/usr/local/bin/claude\"])" &
      "if(fs.existsSync(p))return " & enumName & ".Ready;" &
      "try{require(\"child_process\").execSync(\"which claude\",{encoding:\"utf-8\"});return " & enumName & ".Ready}catch(e2){}" &
      "return " & enumName & ".NotInstalled}catch(err){return " & enumName & ".NotInstalled}}" &
      "if(await this.getLocalBinaryPath())return " & enumName & ".Ready;" &
      "const " & varName & "=this.getHostTarget();" &
      "if(this.preparingPromise)return " & enumName & ".Updating;" &
      "if(await this.binaryExistsForTarget(" & varName & ",this.requiredVersion))"
    let s = mm.matchBounds
    content = content[0 ..< s.a] & replacement & content[s.b + 1 .. ^1]
    count3 = 1
  if count3 >= 1:
    echo &"  [OK] getStatus(): {count3} match(es)"
  elif content.contains("async getStatus(){if(process.platform===\"linux\")"):
    echo "  [OK] getStatus(): already patched"
  else:
    echo "  [FAIL] getStatus(): 0 matches, expected >= 1"
    failed = true

  if failed:
    echo "  [FAIL] Some patterns did not match"
    raise newException(ValueError, "fix_claude_code: some patterns did not match")

  result = content

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_claude_code <file>"
    quit(1)
  let file = paramStr(1)
  echo "=== Patch: fix_claude_code ==="
  echo &"  Target: {file}"
  let input = readFile(file)
  let output = apply(input)
  if output != input:
    writeFile(file, output)
    echo "  [PASS] All patterns matched and applied"
  else:
    echo "  [WARN] No changes made (patterns may have already been applied)"
