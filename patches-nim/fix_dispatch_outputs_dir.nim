# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
# Nim port of fix_dispatch_outputs_dir.py.
# Uses std/nre (PCRE) because pattern has backreferences.

import std/[os, strformat, strutils]
import std/nre

const ExpectedPatches = 1

proc apply*(input: string): string =
  var content = input
  var patchesApplied = 0

  # Patch A: openOutputsDir child fallback
  let pattern = re"""async openOutputsDir\(([\w$]+)\)\{const ([\w$]+)=([\w$]+)\.getOutputsDir\(\1\);([\w$]+)\.info\(`LocalAgentModeSessions\.openOutputsDir: sessionId=\$\{\1\}, outputsDir=\$\{\2\}`\);const ([\w$]+)=await ([\w$]+)\.shell\.openPath\(\2\);\5&&\4\.error\(`Failed to open outputs directory: \$\{\2\}, error: \$\{\5\}`\)\}"""

  let alreadyA = "[openOutputsDir] outputs empty, scanning child sessions" in content
  if alreadyA:
    echo "  [OK] A openOutputsDir: already patched (skipped)"
    inc patchesApplied
  else:
    var count = 0
    content = content.replace(pattern, proc (m: RegexMatch): string =
      inc count
      let p = m.captures[0]  # param
      let d = m.captures[1]  # outputs dir var
      let c = m.captures[2]  # class instance
      let L = m.captures[3]  # logger
      let s = m.captures[4]  # error var
      let E = m.captures[5]  # electron module

      "async openOutputsDir(" & p & "){" &
      "const " & d & "=" & c & ".getOutputsDir(" & p & ");" &
      L & ".info(`LocalAgentModeSessions.openOutputsDir: sessionId=${" & p & "}, outputsDir=${" & d & "}`);" &
      "let _td=" & d & ";" &
      "try{" &
      "const _fs=require(\"fs\"),_pa=require(\"path\");" &
      "const _fl=_fs.readdirSync(" & d & ").filter(f=>!f.startsWith(\".\"));" &
      "if(_fl.length===0){" &
      L & ".info(\"[openOutputsDir] outputs empty, scanning child sessions...\");" &
      "const _ad=_pa.dirname(_pa.dirname(" & d & ".includes(\"/agent/\")?_pa.dirname(" & d & "):" & d & "));" &
      "try{" &
      "const _en=_fs.readdirSync(_ad,{withFileTypes:true});" &
      "for(const _et of _en){" &
      "if(!_et.isDirectory()||_et.name===\"agent\")continue;" &
      "const _co=_pa.join(_ad,_et.name,\"outputs\");" &
      "try{" &
      "const _cf=_fs.readdirSync(_co).filter(f=>!f.startsWith(\".\"));" &
      "if(_cf.length>0){" & L & ".info(`[openOutputsDir] found files in child: ${_co}`);_td=_co;break}" &
      "}catch(_e){}" &
      "}" &
      "}catch(_e){}" &
      "}" &
      "}catch(_e){}" &
      "const " & s & "=await " & E & ".shell.openPath(_td);" &
      s & "&&" & L & ".error(`Failed to open outputs directory: ${_td}, error: ${" & s & "}`)}"
    )
    if count == 1:
      echo "  [OK] A openOutputsDir: child session fallback added"
      inc patchesApplied
    else:
      echo &"  [FAIL] A openOutputsDir: expected 1 match, found {count}"

  if patchesApplied < ExpectedPatches:
    echo &"  [FAIL] Only {patchesApplied}/{ExpectedPatches} patches applied"
    raise newException(ValueError, "fix_dispatch_outputs_dir: patches not fully applied")

  result = content

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_dispatch_outputs_dir <path_to_index.js>"
    quit(1)
  let file = paramStr(1)
  echo "=== Patch: fix_dispatch_outputs_dir ==="
  echo &"  Target: {file}"
  let input = readFile(file)
  let output = apply(input)
  if output != input:
    writeFile(file, output)
    echo "  [PASS] Dispatch outputs directory fallback added"
  else:
    echo "  [OK] Already patched, no changes needed"
