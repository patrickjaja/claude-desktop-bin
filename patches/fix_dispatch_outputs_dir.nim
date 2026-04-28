# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
# Fix "Show folder" opening empty outputs directory for dispatch sessions.
# Scans sibling session directories for child outputs when parent is empty.
# Uses std/nre for backreference support in patterns.

import std/[os, strformat, strutils, options]
import std/nre

const EXPECTED_PATCHES = 1

proc apply*(input: string): string =
  result = input
  var patchesApplied = 0

  let alreadyA = "[openOutputsDir] outputs empty, scanning child sessions" in result
  if alreadyA:
    echo "  [OK] A openOutputsDir: already patched (skipped)"
    patchesApplied += 1
  else:
    # Pattern uses backreferences \1, \5 to match repeated variable names
    let patternA =
      re"""async openOutputsDir\(([\w$]+)\)\{const ([\w$]+)=([\w$]+)\.getOutputsDir\(\1\);([\w$]+)\.info\(`LocalAgentModeSessions\.openOutputsDir: sessionId=\$\{\1\}, outputsDir=\$\{\2\}`\);const ([\w$]+)=await ([\w$]+)\.shell\.openPath\(\2\);\5&&\4\.error\(`Failed to open outputs directory: \$\{\2\}, error: \$\{\5\}`\)\}"""

    let m = result.find(patternA)
    if m.isSome:
      let match = m.get
      let p = match.captures[0] # param name
      let d = match.captures[1] # outputs dir var
      let c = match.captures[2] # class instance
      let L = match.captures[3] # logger
      let sv = match.captures[4] # error var
      let E = match.captures[5] # electron module

      let replacement =
        "async openOutputsDir(" & p & "){" & "const " & d & "=" & c & ".getOutputsDir(" &
        p & ");" & L & ".info(`LocalAgentModeSessions.openOutputsDir: sessionId=${" & p &
        "}, outputsDir=${" & d & "}`);" & "let _td=" & d & ";" & "try{" &
        "const _fs=require(\"fs\"),_pa=require(\"path\");" & "const _fl=_fs.readdirSync(" &
        d & ").filter(f=>!f.startsWith(\".\"));" & "if(_fl.length===0){" & L &
        ".info(\"[openOutputsDir] outputs empty, scanning child sessions...\");" &
        "const _ad=_pa.dirname(_pa.dirname(" & d & ".includes(\"/agent/\")?_pa.dirname(" &
        d & "):" & d & "));" & "try{" &
        "const _en=_fs.readdirSync(_ad,{withFileTypes:true});" & "for(const _et of _en){" &
        "if(!_et.isDirectory()||_et.name===\"agent\")continue;" &
        "const _co=_pa.join(_ad,_et.name,\"outputs\");" & "try{" &
        "const _cf=_fs.readdirSync(_co).filter(f=>!f.startsWith(\".\"));" &
        "if(_cf.length>0){" & L &
        ".info(`[openOutputsDir] found files in child: ${_co}`);_td=_co;break}" &
        "}catch(_e){}" & "}" & "}catch(_e){}" & "}" & "}catch(_e){}" & "const " & sv &
        "=await " & E & ".shell.openPath(_td);" & sv & "&&" & L &
        ".error(`Failed to open outputs directory: ${_td}, error: ${" & sv & "}`)" & "}"

      result =
        result[0 ..< match.matchBounds.a] & replacement &
        result[match.matchBounds.b + 1 .. ^1]
      echo "  [OK] A openOutputsDir: child session fallback added"
      patchesApplied += 1
    else:
      echo "  [FAIL] A openOutputsDir: pattern not found"

  if patchesApplied < EXPECTED_PATCHES:
    raise newException(
      ValueError,
      &"fix_dispatch_outputs_dir: Only {patchesApplied}/{EXPECTED_PATCHES} patches applied",
    )

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_dispatch_outputs_dir <file>"
    quit(1)
  let file = paramStr(1)
  echo "=== Patch: fix_dispatch_outputs_dir ==="
  echo &"  Target: {file}"
  if not fileExists(file):
    echo &"  [FAIL] File not found: {file}"
    quit(1)
  let input = readFile(file)
  let output = apply(input)
  if output != input:
    writeFile(file, output)
    echo "  [PASS] Dispatch outputs directory fallback added"
  else:
    echo "  [OK] Already patched, no changes needed"
