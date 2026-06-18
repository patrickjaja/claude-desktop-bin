# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
#
# Make the built-in agent/Cowork terminal spawn a Linux shell instead of
# PowerShell.
#
# The upstream shell-selection helper is hardcoded to PowerShell on every
# platform:
#
#   function <minified>(){return{shell:"powershell.exe",args:[]}}
#
# Its result is fed straight into node-pty's `pty.spawn(shell, args, ...)`
# inside LocalSessions.startShellPty (and the bash-PTY path). On Linux
# `powershell.exe` is not on PATH, so spawn-helper's execvp(3) fails and the
# PTY dies immediately. The renderer shows "Shell exited." and the main log
# records:
#
#   Shell PTY for session local_... exited with code 1
#
# (verified: forking `powershell.exe` through the bundled pty.node/spawn-helper
# yields exactly `execvp(3) failed.: No such file or directory` + exit code 1.)
#
# Fix: rewrite ONLY the shell string value into a platform-aware ternary so the
# user's login shell ($SHELL, falling back to /bin/bash) is used off-Windows.
# The `args` value and the surrounding function are left untouched.
#
# Robustness notes (this pattern is intentionally minimal so it survives
# upstream re-minification):
#   - Anchors on `shell:"powershell.exe"` only. The `shell` key is a semantic
#     node-pty option name (not minified) and "powershell.exe" is the Windows
#     default shell Anthropic is unlikely to rename.
#   - Does NOT depend on the (minified, per-release) function name, on the
#     `args:[]` value, or on any surrounding structure.
#   - Whitespace- and quote-style-tolerant (`\s*`, `["']`).
#   - The replacement is Windows-semantics-preserving: on win32 it still
#     evaluates to "powershell.exe", so even an accidental second match
#     elsewhere in the bundle stays correct on Windows and sane on Linux.
#   - `shell:"powershell.exe"` occurs exactly once in the bundle today
#     (the bare string "powershell.exe" appears 8x, but only here behind a
#     `shell:` key), so a single match is expected.

import std/[os, strformat, strutils]
import regex

const EXPECTED_PATCHES = 1

# Platform-aware shell value. On win32 it reproduces the original verbatim;
# everywhere else it uses the user's login shell with a /bin/bash fallback.
const SHELL_EXPR =
  """process.platform==="win32"?"powershell.exe":process.env.SHELL||"/bin/bash""""

# Unique marker proving our replacement is already present (idempotency).
# "/bin/bash" does not otherwise occur in the upstream bundle.
const PATCHED_MARKER = """process.env.SHELL||"/bin/bash""""

proc apply*(input: string): string =
  result = input
  var patchesApplied = 0

  if PATCHED_MARKER in result:
    echo "  [INFO] Terminal shell already rewritten for Linux"
    patchesApplied += 1
  else:
    # Group 1: the `shell:` key (with optional whitespace), preserved verbatim.
    # The remainder (the "powershell.exe" string literal) is replaced.
    let pattern = re2"""(shell\s*:\s*)["']powershell\.exe["']"""

    var count = 0
    result = result.replace(
      pattern,
      proc(m: RegexMatch2, s: string): string =
        inc count
        s[m.group(0)] & SHELL_EXPR,
    )
    if count > 0:
      echo &"  [OK] Terminal shell rewritten to $SHELL/bin/bash: {count} match(es)"
      patchesApplied += 1
    else:
      echo "  [FAIL] Could not find `shell:\"powershell.exe\"` selector"
      echo "  [HINT] Search for 'powershell.exe' near 'args:[]' (function returning {shell,args})"

  if patchesApplied < EXPECTED_PATCHES:
    echo &"  [FAIL] Only {patchesApplied}/{EXPECTED_PATCHES} patches applied"
    quit(1)

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_terminal_shell_linux <file>"
    quit(1)
  let filePath = paramStr(1)
  echo "=== Patch: fix_terminal_shell_linux ==="
  echo &"  Target: {filePath}"
  if not fileExists(filePath):
    echo &"  [FAIL] File not found: {filePath}"
    quit(1)
  let input = readFile(filePath)
  let output = apply(input)
  if output != input:
    writeFile(filePath, output)
    echo "  [PASS] Terminal shell patched successfully"
  else:
    echo "  [PASS] No changes needed (already patched)"
