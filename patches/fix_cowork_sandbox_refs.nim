# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
#
# Nim port of fix_cowork_sandbox_refs.py — produces byte-identical output.
#
# 4 sub-patches, each wraps a sandbox/VM-accurate phrase in a runtime
# ternary keyed on globalThis.__coworkKvmMode (set by fix_cowork_linux).
#
# Injection style depends on the enclosing JS string literal:
#   "…target…"  → close dquote + concat + reopen:
#                 "…"+(globalThis.__coworkKvmMode?"orig":"new")+"…"
#   `…target…`  → template interpolation:
#                 `…${globalThis.__coworkKvmMode?"orig":"new"}…`
#
# No "already patched" fast path — missing anchors are hard failures.

import std/[os, strformat, strutils, options]
import std/nre

proc replaceFirstRe(content: var string, pattern: Regex,
                    subFn: proc(m: RegexMatch): string): int =
  let maybe = content.find(pattern)
  if maybe.isNone: return 0
  let m = maybe.get()
  let bounds = m.matchBounds
  content = content[0 ..< bounds.a] & subFn(m) & content[bounds.b + 1 .. ^1]
  return 1

proc classifyContext(content: string, pos: int): string =
  ## Whichever of " / ` is nearer before `pos` wins. Matches Python's
  ## rfind(b"`", 0, pos) / rfind(b'"', 0, pos) comparison: lastBt > lastDq
  ## means the backtick is closer to pos.
  let lastBt = content.rfind("`", last = pos - 1)
  let lastDq = content.rfind("\"", last = pos - 1)
  if lastBt > lastDq: "backtick" else: "dquote"

proc injectTernary(context, orig, newStr: string): string =
  let ternary = "globalThis.__coworkKvmMode?\"" & orig & "\":\"" & newStr & "\""
  if context == "backtick":
    "${" & ternary & "}"
  else:
    "\"+(" & ternary & ")+\""

proc replaceSubstringContextAware(content: var string, orig, newStr: string): int =
  ## Walk left-to-right, replace each occurrence with a context-aware
  ## ternary. Each replacement's context is classified against the prefix
  ## of the pre-edit string so fresh quotes/backticks we inject don't
  ## pollute later context lookups.
  var buf = newStringOfCap(content.len + 128)
  var cursor = 0
  var count = 0
  while true:
    let pos = content.find(orig, cursor)
    if pos < 0:
      buf.add content[cursor .. ^1]
      break
    let context = classifyContext(content, pos)
    buf.add content[cursor ..< pos]
    buf.add injectTernary(context, orig, newStr)
    cursor = pos + orig.len
    inc count
  content = buf
  return count

proc apply*(input: string): string =
  var content = input
  let original = input
  var patchesApplied = 0
  const EXPECTED_PATCHES = 4

  # ── Patch A: Bash tool description ─────────────────────────────
  block:
    let pat = re"""("Run a shell command in the session's isolated Linux workspace\.[^"]*?/sessions/")(\+[\w$.]+\+)("/mnt/[^"]*?")"""

    # Native-mode rewrites (byte-for-byte identical to the Python source).
    const nativeHalf1 =
      "\"Run a shell command on the host Linux system." &
      " There is no VM or sandbox \\u2014 commands execute directly" &
      " on the user\\u2019s computer." &
      " Each bash call is independent (no cwd/env carryover)." &
      " Use absolute paths.\""
    const nativeHalf2 = "\"\""

    let n = replaceFirstRe(content, pat, proc(m: RegexMatch): string =
      let origHalf1 = m.captures[0]
      let concat = m.captures[1]
      let origHalf2 = m.captures[2]
      "(globalThis.__coworkKvmMode?" & origHalf1 & ":" & nativeHalf1 & ")" &
        concat &
        "(globalThis.__coworkKvmMode?" & origHalf2 & ":" & nativeHalf2 & ")"
    )
    if n == 1:
      echo "  [OK] A bash tool description: wrapped in runtime ternary"
      inc patchesApplied
    else:
      echo "  [FAIL] A bash tool description: pattern not found"

  # ── Patch B: Cowork identity system prompt ─────────────────────
  block:
    const origB = "Claude runs in a lightweight Linux VM on the user's computer, which provides a secure sandbox for executing code while allowing controlled access to a workspace folder."
    const newB = "Claude runs directly on the user's Linux computer with full access to the local filesystem and installed tools. There is no VM or sandbox."

    let n = replaceSubstringContextAware(content, origB, newB)
    if n >= 1:
      echo &"  [OK] B cowork identity prompt: wrapped {n} occurrence(s)"
      inc patchesApplied
    else:
      echo "  [FAIL] B cowork identity prompt: pattern not found"

  # ── Patch C: Computer use high-level explanation ───────────────
  block:
    const origC = "Claude runs in a lightweight Linux VM (Ubuntu 22) on the user's computer. This VM provides a secure sandbox for executing code while allowing controlled access to user files."
    const newC = "Claude runs directly on the user's Linux computer. Commands execute on the host system with full access to local files and tools. There is no VM or sandbox."

    let n = replaceSubstringContextAware(content, origC, newC)
    if n >= 1:
      echo &"  [OK] C computer use explanation: wrapped {n} occurrence(s)"
      inc patchesApplied
    else:
      echo "  [FAIL] C computer use explanation: pattern not found"

  # ── Patch D: "isolated Linux environment" variants ────────────
  block:
    let variants = [
      ("The isolated Linux environment", "The host Linux environment"),
      ("an isolated Linux environment", "the host Linux environment"),
    ]
    var totalD = 0
    for (origSub, newSub) in variants:
      totalD += replaceSubstringContextAware(content, origSub, newSub)
    if totalD >= 1:
      echo &"  [OK] D isolated Linux environment: wrapped {totalD} occurrence(s)"
      inc patchesApplied
    else:
      echo "  [FAIL] D isolated Linux environment: pattern not found"

  # ── Checks ────────────────────────────────────────────────────
  if patchesApplied < EXPECTED_PATCHES:
    raise newException(ValueError,
      &"Only {patchesApplied}/{EXPECTED_PATCHES} patches applied")

  let originalDelta = original.count('{') - original.count('}')
  let patchedDelta = content.count('{') - content.count('}')
  if originalDelta != patchedDelta:
    let diff = patchedDelta - originalDelta
    raise newException(ValueError, &"Patch introduced brace imbalance: {diff:+d} unmatched braces")

  echo &"  [PASS] All {patchesApplied} sandbox/VM references wrapped for runtime selection"
  result = content

when isMainModule:
  let file = paramStr(1)
  echo "=== Patch: fix_cowork_sandbox_refs ==="
  echo &"  Target: {file}"
  let input = readFile(file)
  let output = apply(input)
  if output != input:
    writeFile(file, output)
