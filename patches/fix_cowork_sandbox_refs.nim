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
  const EXPECTED_PATCHES = 8

  # ── Patch A: Bash tool description ─────────────────────────────
  # Upstream v1.7196.1 collapsed the prior three-piece concat
  #   "...sessions/" + VAR + "/mnt/..."
  # into a single literal that uses "<session>" as an in-string placeholder.
  # Match the whole literal and wrap it in the runtime ternary.
  block:
    let patNew =
      re"""("Run a shell command in the session's isolated Linux workspace\.[^"]*?wait a few seconds and retry\.")"""
    let patOld =
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

    var n = replaceFirstRe(
      content,
      patNew,
      proc(m: RegexMatch): string =
        let origStr = m.captures[0]
        "(globalThis.__coworkKvmMode?" & origStr & ":" &
          "globalThis.__coworkSandboxMode?" & sandboxHalf1 & ":" &
          nativeHalf1 & ")",
    )
    if n == 0:
      # Fallback to the pre-v1.7196.1 three-piece concat pattern.
      n = replaceFirstRe(
        content,
        patOld,
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

  # ── Patch E: "Files you create in the sandbox" sentence ───────
  # Two occurrences in the CU section, one per template-literal var
  # name (the workspace path interpolation). The minified name shifts
  # across upstream releases (v1.6608: ${AA}; v1.7196.1: ${eA}; the
  # first variant has stayed at ${e}). Match with [\w$]+ so this
  # survives future renames. In native cowork mode the whole sentence
  # is misleading — there is no sandbox, files Claude creates are
  # directly visible to host desktop apps. Omit the sentence in
  # native; keep upstream in kvm/sandbox.
  block:
    let patE =
      re"""Files you create in the sandbox \(under \\`\$\{[\w$]+\}\\` or \\`/tmp\\`\) do NOT exist on the user's machine\. If you put a command or file path in the user's clipboard, or type into one of their apps, the path must exist on THEIR computer — not a sandbox path they can't reach\."""
    var hitsE = 0
    content = content.replace(
      patE,
      proc(m: RegexMatch): string =
        inc hitsE
        "${(globalThis.__coworkKvmMode||globalThis.__coworkSandboxMode)?`" &
          m.match & "`:\"\"}",
    )
    if hitsE >= 2:
      echo &"  [OK] E sandbox-file warning: omitted in native ({hitsE} occurrences)"
      inc patchesApplied
    else:
      echo &"  [FAIL] E sandbox-file warning: expected 2, found {hitsE}"

  # ── Patch F: Shell access — "Paths in bash differ ... translate." ──
  # The block interpolates 3 template-vars on the mapping line and 2
  # path-vars on the example line. All five names are minified and
  # have shifted across releases (v1.6608: ${Ae}${EA}${W} / ${dA},${nA};
  # v1.7196.1: ${uA}${W}${IA} / ${nA},${lA}). Match each with [\w$]+
  # so renames don't break the patch.
  # In native mode bash and the file tools share the same filesystem;
  # the path-mapping block (and the "translate" instruction) is wrong
  # and has actually misled the model in practice. Replace with a
  # single line clarifying that no translation is needed.
  block:
    let patF =
      re"""Paths in bash differ from what file tools \(Read/Write/Edit\) see:\n\$\{[\w$]+\}\$\{[\w$]+\}\$\{[\w$]+\}\n\nSo a file you Read at \$\{[\w$]+\}/foo\.txt is reached in bash at \$\{[\w$]+\}/foo\.txt — use the mapping above to translate\."""
    var hitsF = 0
    content = content.replace(
      patF,
      proc(m: RegexMatch): string =
        inc hitsF
        "${(globalThis.__coworkKvmMode||globalThis.__coworkSandboxMode)?`" &
          m.match &
          "`:\"Bash and the file tools (Read/Write/Edit) see the same filesystem \\u2014 no path translation needed; use absolute paths directly.\"}",
    )
    if hitsF == 1:
      echo "  [OK] F shell-access path mapping: native gets same-fs note"
      inc patchesApplied
    else:
      echo &"  [FAIL] F shell-access path mapping: expected 1, found {hitsF}"

  # ── Patch G: Skill scripts via VM path ─────────────────────────
  # The "VM path above" wording only makes sense when there IS a
  # separate VM-side path. In native mode the file-tool path and the
  # bash path are the same, so this sentence is wrong (and the "above"
  # reference dangles since Patch F removes the mapping). Suppress in
  # native cowork mode.
  # The gating var was `M` in earlier releases and `N` in v1.7196.1+;
  # match with [\w$]+ to ride out future renames.
  block:
    let patG =
      re"""\+\(([\w$]+)\?" Skill scripts can be run via bash using the VM path above\."\:""\)\+"""
    let n = replaceFirstRe(
      content,
      patG,
      proc(m: RegexMatch): string =
        let gateVar = m.captures[0]
        "+((" & gateVar &
          "&&(globalThis.__coworkKvmMode||globalThis.__coworkSandboxMode))?\"" &
          " Skill scripts can be run via bash using the VM path above.\":\"\")+",
    )
    if n == 1:
      echo "  [OK] G skill-scripts VM path: cowork-only"
      inc patchesApplied
    else:
      echo "  [FAIL] G skill-scripts VM path: anchor not found"

  # ── Patch H: "Linux environment boots in the background" ───────
  # No Linux environment boots in native cowork mode — the shell is
  # just the user's host. Omit the sentence (and its leading blank
  # line) in native; keep upstream in kvm/sandbox.
  block:
    const anchor =
      "\n\nThe Linux environment boots in the background. If bash returns \"Workspace still starting\", wait a few seconds and retry."
    if content.contains(anchor):
      let repl =
        "${(globalThis.__coworkKvmMode||globalThis.__coworkSandboxMode)?`" &
        anchor & "`:\"\"}"
      content = content.replace(anchor, repl)
      echo "  [OK] H workspace-starting notice: cowork-only"
      inc patchesApplied
    else:
      echo "  [FAIL] H workspace-starting notice: anchor not found"

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
