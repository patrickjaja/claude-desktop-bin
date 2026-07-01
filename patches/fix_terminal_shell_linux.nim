# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
#
# Regression guard: the built-in agent/Cowork terminal spawns a real POSIX login
# shell on Linux (no longer PowerShell).
#
# History: the upstream shell-selection helper used to be hardcoded to PowerShell
# on every platform — `function X(){return{shell:"powershell.exe",args:[]}}` — so
# the PTY died instantly on Linux (`execvp(3) failed.: No such file or directory`).
# We rewrote the `shell:"powershell.exe"` value into a `$SHELL → /bin/bash → /bin/sh`
# ternary.
#
# The official Linux .deb upstreamed a proper resolver and the `powershell.exe`
# default is gone:
#     function t6i(){const A=process.env.SHELL;if(A!=null&&A.startsWith("/")&&<fs>.existsSync(A))return A;
#                    for(const t of CWe)if(<fs>.existsSync(t.path)&&...)return t.path;
#                    for(const t of CWe)if(<fs>.existsSync(t.path))return t.path;return ...}
#     function urt(){return{shell:t6i(),args:["-l"]}}
# where the candidate list `CWe` ends with `{path:"/bin/sh"}`. This is a superset of
# our old behavior (prefers $SHELL, then known shells by existence, then /bin/sh),
# and it is the default on all platforms — there is no `shell:"powershell.exe"`
# string left to rewrite.
#
# Per CLAUDE.md Rule 6 (feature upstreamed -> regression guard, never silent delete),
# this patch now POSITIVELY asserts the native resolver is present:
#   - a shell-options factory `return{shell:<fn>(),args:["-l"]}` exists, AND
#   - the resolver reads process.env.SHELL and falls back to "/bin/sh".
# If a future bump reintroduces a hardcoded `shell:"powershell.exe"` default (or
# removes the /bin/sh fallback), this FAILs loud so the dead-PTY regression is
# caught at build time.

import std/[os, strformat, strutils]
import regex

const EXPECTED_PATCHES = 1

proc apply*(input: string): string =
  result = input
  var patchesApplied = 0

  # Hard regression: a re-introduced hardcoded PowerShell default would break the
  # Linux PTY again. Assert it is NOT present as a shell-options value.
  var psm: RegexMatch2
  if input.find(re2"""shell\s*:\s*["']powershell\.exe["']""", psm):
    echo "  [FAIL] A hardcoded `shell:\"powershell.exe\"` default reappeared — Linux PTY would die"
    echo "         Re-audit: upstream regressed the shell selector; restore the $SHELL→/bin/sh rewrite."
    quit(1)

  # Positive assertion 1: the shell-options factory returns shell:<resolver>() with
  # login args. Anchored on the semantic `shell:`/`args:` keys (not minified names).
  var fm: RegexMatch2
  if not input.find(re2"""return\{shell:[\w$]+\(\),args:\["-l"\]\}""", fm):
    echo "  [FAIL] Native shell-options factory `return{shell:<fn>(),args:[\"-l\"]}` NOT found"
    echo "         Debug: rg -o 'return\\{shell:[\\w$]+\\(\\),args:\\[\"-l\"\\]\\}' index.js"
    quit(1)

  # Positive assertion 2: the resolver itself reads $SHELL and has a /bin/sh anchor
  # in its candidate list (the universal fallback our old patch also relied on).
  if "process.env.SHELL" notin input or "/bin/sh" notin input:
    echo "  [FAIL] Native shell resolver missing process.env.SHELL or /bin/sh fallback"
    quit(1)

  echo "  [OK] Native POSIX shell resolver present (return{shell:<fn>(),args:[\"-l\"]}, " &
    "$SHELL→…→/bin/sh) — regression guard satisfied"
  patchesApplied += 1

  if patchesApplied < EXPECTED_PATCHES:
    echo &"  [FAIL] Only {patchesApplied}/{EXPECTED_PATCHES} patches applied"
    quit(1)

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_terminal_shell_linux <file>"
    quit(1)
  let filePath = paramStr(1)
  echo "=== Patch: fix_terminal_shell_linux (regression guard) ==="
  echo &"  Target: {filePath}"
  if not fileExists(filePath):
    echo &"  [FAIL] File not found: {filePath}"
    quit(1)
  let input = readFile(filePath)
  let output = apply(input)
  if output != input:
    writeFile(filePath, output)
  echo "  [PASS] Native POSIX shell confirmed on Linux (no patch needed)"
