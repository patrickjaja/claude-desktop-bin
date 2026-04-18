# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
#
# Fix cowork sandbox/VM references for Linux.
#
# On macOS/Windows, cowork runs inside a lightweight Linux VM (Ubuntu 22) that
# provides an isolated sandbox. On Linux with the native Go backend
# (claude-cowork-service), there is NO VM -- Claude Code runs directly on the
# host system. The upstream system prompts and tool descriptions falsely tell
# the model it is in a sandbox, causing it to claim it runs in "an isolated
# Linux sandbox (Ubuntu 22)", believe files it creates do not exist on the
# user's machine, and think it has restricted filesystem access.
#
# What we patch:
#   A) Bash tool description: "isolated Linux workspace" -> "host Linux system"
#   B) Cowork identity prompt: "lightweight Linux VM" -> "directly on the host"
#   C) Computer use explanation: "lightweight Linux VM (Ubuntu 22)" -> host
#   D) System prompt: "isolated Linux environment" -> "host Linux system" (3x)

import std/[os, strformat, strutils]
import std/nre

const EXPECTED_PATCHES = 4

proc apply*(input: string): string =
  result = input
  var patchesApplied = 0

  # -- Patch A: Bash tool description --
  let alreadyA = "There is no VM or sandbox" in result and "isolated Linux workspace" notin result
  if alreadyA:
    echo "  [OK] A bash tool description: already patched (skipped)"
    inc patchesApplied
  else:
    let patternA = re"""(?s)"Run a shell command in the session's isolated Linux workspace\.[^"]*?/sessions/"(\+[\w$.]+\+)"/mnt/[^"]*?""""
    var countA = 0
    result = result.replace(patternA, proc(m: RegexMatch): string =
      inc countA
      let dynamicConcat = m.captures[0]
      "\"Run a shell command on the host Linux system." &
        " There is no VM or sandbox \\u2014 commands execute directly" &
        " on the user\\u2019s computer." &
        " Each bash call is independent (no cwd/env carryover)." &
        " Use absolute paths.\"" &
        dynamicConcat &
        "\"unused\""
    )
    if countA == 1:
      echo "  [OK] A bash tool description: replaced with host-aware text"
      inc patchesApplied
    else:
      echo "  [FAIL] A bash tool description: pattern not found"

  # -- Patch B: Cowork identity system prompt --
  let oldB = "Claude runs in a lightweight Linux VM on the user's computer, which provides a secure sandbox for executing code while allowing controlled access to a workspace folder."
  let newB = "Claude runs directly on the user's Linux computer with full access to the local filesystem and installed tools. There is no VM or sandbox."

  let alreadyB = "Claude runs directly on the user's Linux computer with full" in result
  if alreadyB:
    echo "  [OK] B cowork identity prompt: already patched (skipped)"
    inc patchesApplied
  else:
    let countB = result.count(oldB)
    if countB == 1:
      result = result.replace(oldB, newB)
      echo "  [OK] B cowork identity prompt: replaced with Linux-accurate text"
      inc patchesApplied
    else:
      echo &"  [FAIL] B cowork identity prompt: expected 1 occurrence, found {countB}"

  # -- Patch C: Computer use high-level explanation --
  let oldC = "Claude runs in a lightweight Linux VM (Ubuntu 22) on the user's computer. This VM provides a secure sandbox for executing code while allowing controlled access to user files."
  let newC = "Claude runs directly on the user's Linux computer. Commands execute on the host system with full access to local files and tools. There is no VM or sandbox."

  let alreadyC = "Commands execute on the host system with full access to local" in result
  if alreadyC:
    echo "  [OK] C computer use explanation: already patched (skipped)"
    inc patchesApplied
  else:
    let countC = result.count(oldC)
    if countC == 1:
      result = result.replace(oldC, newC)
      echo "  [OK] C computer use explanation: replaced with Linux-accurate text"
      inc patchesApplied
    else:
      echo &"  [FAIL] C computer use explanation: expected 1 occurrence, found {countC}"

  # -- Patch D: "isolated Linux environment" -> "host Linux environment" --
  let oldD1 = "The isolated Linux environment"
  let newD1 = "The host Linux environment"
  let oldD2 = "an isolated Linux environment"
  let newD2 = "the host Linux environment"

  let alreadyD = result.count(oldD1) == 0 and result.count(oldD2) == 0 and "host Linux environment" in result
  if alreadyD:
    echo "  [OK] D isolated Linux environment: already patched (skipped)"
    inc patchesApplied
  else:
    let countD1 = result.count(oldD1)
    let countD2 = result.count(oldD2)
    let total = countD1 + countD2
    if total >= 1:
      result = result.replace(oldD1, newD1)
      result = result.replace(oldD2, newD2)
      echo &"  [OK] D isolated Linux environment: replaced {total} occurrences ({countD1} 'The' + {countD2} 'an')"
      inc patchesApplied
    else:
      echo "  [FAIL] D isolated Linux environment: pattern not found"

  if patchesApplied < EXPECTED_PATCHES:
    echo &"  [FAIL] Only {patchesApplied}/{EXPECTED_PATCHES} patches applied"
    quit(1)

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_cowork_sandbox_refs <path_to_index.js>"
    quit(1)

  let filePath = paramStr(1)
  echo "=== Patch: fix_cowork_sandbox_refs ==="
  echo "  Target: " & filePath

  if not fileExists(filePath):
    echo "  [FAIL] File not found: " & filePath
    quit(1)

  let input = readFile(filePath)
  let output = apply(input)

  if output != input:
    writeFile(filePath, output)
    echo &"  [PASS] All {EXPECTED_PATCHES} sandbox/VM references fixed for Linux"
  else:
    echo "  [OK] Already patched, no changes needed"
