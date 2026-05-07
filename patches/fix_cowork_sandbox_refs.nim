# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
#
# Nim port of fix_cowork_sandbox_refs.py — produces byte-identical output.
#
# 4 sub-patches, each wraps a sandbox/VM-accurate phrase in a runtime
# three-way ternary keyed on globalThis.__coworkKvmMode and
# globalThis.__coworkSandboxMode (both set by fix_cowork_linux):
#
#   __coworkKvmMode      → original kvm/VM phrasing
#   __coworkSandboxMode  → bwrap sandbox phrasing
#   else                 → native (host, no isolation) phrasing
#
# Injection style depends on the enclosing JS string literal:
#   "…target…"  → close dquote + concat + reopen:
#                 "…"+(globalThis.__coworkKvmMode?"kvm":
#                       globalThis.__coworkSandboxMode?"sandbox":"native")+"…"
#   `…target…`  → template interpolation:
#                 `…${globalThis.__coworkKvmMode?"kvm":
#                       globalThis.__coworkSandboxMode?"sandbox":"native"}…`
#
# No "already patched" fast path — missing anchors are hard failures.

import std/[os, strformat, strutils, options]
import std/nre

proc replaceFirstRe(
    content: var string, pattern: Regex, subFn: proc(m: RegexMatch): string
): int =
  let maybe = content.find(pattern)
  if maybe.isNone:
    return 0
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

proc injectTernary(context, kvmStr, sandboxStr, nativeStr: string): string =
  let ternary =
    "globalThis.__coworkKvmMode?\"" & kvmStr &
    "\":globalThis.__coworkSandboxMode?\"" & sandboxStr &
    "\":\"" & nativeStr & "\""
  if context == "backtick":
    "${" & ternary & "}"
  else:
    "\"+(" & ternary & ")+\""

proc replaceSubstringContextAware(
    content: var string, kvmStr, sandboxStr, nativeStr: string
): int =
  ## Walk left-to-right, replace each occurrence of kvmStr (the phrasing
  ## present in the upstream bundle) with a context-aware three-way
  ## ternary. Each replacement's context is classified against the prefix
  ## of the pre-edit string so fresh quotes/backticks we inject don't
  ## pollute later context lookups.
  var buf = newStringOfCap(content.len + 256)
  var cursor = 0
  var count = 0
  while true:
    let pos = content.find(kvmStr, cursor)
    if pos < 0:
      buf.add content[cursor .. ^1]
      break
    let context = classifyContext(content, pos)
    buf.add content[cursor ..< pos]
    buf.add injectTernary(context, kvmStr, sandboxStr, nativeStr)
    cursor = pos + kvmStr.len
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
    let pat =
      re"""("Run a shell command in the session's isolated Linux workspace\.[^"]*?/sessions/")(\+[\w$.]+\+)("/mnt/[^"]*?")"""

    # Native-mode rewrite (byte-for-byte identical to the Python source).
    const nativeHalf1 =
      "\"Run a shell command on the host Linux system." &
      " There is no VM or sandbox \\u2014 commands execute directly" &
      " on the user\\u2019s computer." &
      " Each bash call is independent (no cwd/env carryover)." & " Use absolute paths.\""

    # Sandbox-mode rewrite — bwrap fallback backend.
    const sandboxHalf1 =
      "\"Run a shell command inside a bubblewrap sandbox on the user\\u2019s Linux machine." &
      " Writes are confined to the user-selected workspace and a session outputs" &
      " scratch directory; the host filesystem is otherwise read-only or hidden." &
      " Network egress is filtered through an allowlist proxy." &
      " Each bash call is independent (no cwd/env carryover)." & " Use absolute paths.\""

    let n = replaceFirstRe(
      content,
      pat,
      proc(m: RegexMatch): string =
        let origHalf1 = m.captures[0]
        let concat = m.captures[1]
        let origHalf2 = m.captures[2]
        "(globalThis.__coworkKvmMode?" & origHalf1 & concat & origHalf2 & ":" &
          "globalThis.__coworkSandboxMode?" & sandboxHalf1 & ":" &
          nativeHalf1 & ")",
    )
    if n == 1:
      echo "  [OK] A bash tool description: wrapped in three-way runtime ternary"
      inc patchesApplied
    else:
      echo "  [FAIL] A bash tool description: pattern not found"

  # ── Patch B: Cowork identity system prompt ─────────────────────
  block:
    const kvmB =
      "Claude runs in a lightweight Linux VM on the user's computer, which provides a secure sandbox for executing code while allowing controlled access to a workspace folder."
    const sandboxB =
      "Claude runs inside a bubblewrap sandbox on the user's Linux computer. The sandbox restricts writes to the user-selected workspace and a session outputs directory, exposes most of the host filesystem read-only, and routes network traffic through an allowlist proxy."
    const nativeB =
      "Claude runs directly on the user's Linux computer with full access to the local filesystem and installed tools. There is no VM or sandbox."

    let n = replaceSubstringContextAware(content, kvmB, sandboxB, nativeB)
    if n >= 1:
      echo &"  [OK] B cowork identity prompt: wrapped {n} occurrence(s)"
      inc patchesApplied
    else:
      echo "  [FAIL] B cowork identity prompt: pattern not found"

  # ── Patch C: Computer use high-level explanation ───────────────
  block:
    const kvmC =
      "Claude runs in a lightweight Linux VM (Ubuntu 22) on the user's computer. This VM provides a secure sandbox for executing code while allowing controlled access to user files."
    const sandboxC =
      "Claude runs inside a bubblewrap sandbox on the user's Linux computer. Commands execute on the host as the user but with restricted filesystem scope (writes confined to the user-selected workspace and outputs dir, host otherwise read-only) and an allowlisted network proxy. There is no VM but there is a sandbox."
    const nativeC =
      "Claude runs directly on the user's Linux computer. Commands execute on the host system with full access to local files and tools. There is no VM or sandbox."

    let n = replaceSubstringContextAware(content, kvmC, sandboxC, nativeC)
    if n >= 1:
      echo &"  [OK] C computer use explanation: wrapped {n} occurrence(s)"
      inc patchesApplied
    else:
      echo "  [FAIL] C computer use explanation: pattern not found"

  # ── Patch D: "isolated Linux environment" variants ────────────
  block:
    let variants = [
      ("The isolated Linux environment", "The sandboxed Linux environment", "The host Linux environment"),
      ("an isolated Linux environment", "a sandboxed Linux environment", "the host Linux environment"),
    ]
    var totalD = 0
    for (kvmSub, sandboxSub, nativeSub) in variants:
      totalD += replaceSubstringContextAware(content, kvmSub, sandboxSub, nativeSub)
    if totalD >= 1:
      echo &"  [OK] D isolated Linux environment: wrapped {totalD} occurrence(s)"
      inc patchesApplied
    else:
      echo "  [FAIL] D isolated Linux environment: pattern not found"

  # ── Checks ────────────────────────────────────────────────────
  if patchesApplied < EXPECTED_PATCHES:
    raise newException(
      ValueError, &"Only {patchesApplied}/{EXPECTED_PATCHES} patches applied"
    )

  let originalDelta = original.count('{') - original.count('}')
  let patchedDelta = content.count('{') - content.count('}')
  if originalDelta != patchedDelta:
    let diff = patchedDelta - originalDelta
    raise newException(
      ValueError, &"Patch introduced brace imbalance: {diff:+d} unmatched braces"
    )

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
