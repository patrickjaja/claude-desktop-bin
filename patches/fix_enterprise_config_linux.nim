# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
#
# Enable enterprise config on Linux.
#
# The enterprise config function reads managed configuration:
# - macOS: reads from CFPreferences (MDM profiles)
# - Windows: reads from Windows Registry (Group Policy)
# - Linux: returns {} (no enterprise config support)
#
# This patch adds Linux support by reading from a JSON file at
# /etc/claude-desktop/enterprise.json. If the file doesn't exist
# or is invalid, falls back to {} (preserving current behavior).

import std/[os, strutils]
import regex

const linuxReader =
  """(()=>{try{return JSON.parse(require("fs").readFileSync("/etc/claude-desktop/enterprise.json","utf8"))}catch(e){return{}}})()"""

# v1.13576.0: upstream collapsed the darwin/win32 ternary
#     process.platform==="darwin"?FUNC_D():process.platform==="win32"?FUNC_W():{}
# into a single wrapper that unconditionally calls the win32 registry
# reader (the mac plist reader was removed):
#     function Mei(){const A=Rei();return Object.keys(A).length>0?A:void 0}
# where Rei() reads `SOFTWARE\Policies\...` and yields {} off-Windows.
#
# We patch that wrapper so on Linux it reads /etc/claude-desktop/enterprise.json
# instead of the (empty) registry result:
#     function Mei(){const A=process.platform==="linux"?(...):Rei();return ...}
#
# The wrapper is anchored on the registry-reader fn, whose name we capture
# from its `SOFTWARE\Policies` body so we don't hardcode a minified name.
# The same structure lives in index.pre.js (early bootstrap), so this is
# applied to both files.
proc patchEnterpriseWrapper(
    input: string, required: bool
): tuple[output: string, applied: bool] =
  if "/etc/claude-desktop/enterprise.json" in input:
    echo "  [OK] Already patched (enterprise.json path found)"
    return (input, true)

  let regFnPat =
    re2"""function ([\w$]+)\(\)\{var [\w$]+,[\w$]+;const [\w$]+=`SOFTWARE\\\\Policies"""
  var regMatch: RegexMatch2
  if not input.find(regFnPat, regMatch):
    if required:
      echo "  [FAIL] Could not locate win32 registry reader (SOFTWARE\\Policies fn)"
    else:
      echo "  [INFO] index.pre.js: no SOFTWARE\\Policies registry fn (optional)"
    return (input, false)
  let regFn = input[regMatch.group(0)]

  # Patch the enterprise wrapper that calls the registry reader:
  #   function X(){const Y=<regFn>();return Object.keys(Y).length>0?Y:void 0}
  let pattern = re2(
    """(function [\w$]+\(\)\{const [\w$]+=)(""" & regFn &
      """\(\);return Object\.keys\([\w$]+\)\.length>0)"""
  )
  var count = 0
  let output = input.replace(
    pattern,
    proc(m: RegexMatch2, s: string): string =
      inc count
      # const Y= -> const Y=process.platform==="linux"?(...):
      s[m.group(0)] & """process.platform==="linux"?""" & linuxReader & ":" &
        s[m.group(1)],
  )
  if count >= 1:
    echo "  [OK] Enterprise config Linux reader: " & $count & " match(es)"
    return (output, true)
  else:
    if required:
      echo "  [FAIL] Enterprise config wrapper not found (calls " & regFn & "())"
    else:
      echo "  [INFO] index.pre.js: no enterprise wrapper (optional)"
    return (input, false)

# Promote the upstream "managed config loaded" log from debug to info so a
# successful, non-empty load is visible in main.log at the default log level.
# Upstream logs it at debug:
#     <logger>.debug("Managed config loaded: %o",<redactFn>(<var>))
# There are two variants per bundle: the empty/"none" case (second arg `{}`) and
# the loaded case (second arg a redact-fn call). We promote ONLY the loaded
# case — promoting the "none" case would spam info on every launch without a file.
# The logger var and redact fn are minified and differ per bundle, so we capture
# them with `[\w$]+`. The redact arg may itself be a nested call
# (v1.15200: `yXA(zJ(l))`), so match a fn call whose argument list is non-empty
# and does NOT start with `{` (which excludes the empty/"none" `{}` variant).
# Idempotent: an existing `.info("Managed config loaded: %o",<call>)` counts as
# already applied.
#
# History: this string was "Enterprise config loaded" through v1.14271; upstream
# renamed it to "Managed config loaded" in v1.15200.
proc patchLoadedLogLevel(
    input: string, required: bool
): tuple[output: string, applied: bool] =
  # Already promoted? (loaded variant: arg is a fn call starting with an identifier, not `{}`)
  let donePat = re2"""\.info\("Managed config loaded: %o",[\w$]+\([^{][^)]*\)\)"""
  var dummy: RegexMatch2
  if input.find(donePat, dummy):
    echo "  [OK] Loaded-config log already at info level"
    return (input, true)

  # Match the loaded variant only: ...debug("...",<redactFn>(<non-{ args>))
  # Arg starts with `[\w$]+(` and its first inner char is not `{`, so the
  # empty/"none" `.debug("...",{})` variant is excluded.
  let pattern = re2"""(\.)debug(\("Managed config loaded: %o",[\w$]+\([^{][^)]*\)\))"""
  var count = 0
  let output = input.replace(
    pattern,
    proc(m: RegexMatch2, s: string): string =
      inc count
      s[m.group(0)] & "info" & s[m.group(1)],
  )
  if count >= 1:
    echo "  [OK] Promoted loaded-config log debug->info: " & $count & " match(es)"
    return (output, true)
  else:
    if required:
      echo "  [FAIL] Could not find loaded-config debug log to promote"
    else:
      echo "  [INFO] index.pre.js: no loaded-config debug log (optional)"
    return (input, false)

proc apply*(input: string): string =
  let (output, applied) = patchEnterpriseWrapper(input, required = true)
  if not applied:
    quit(1)
  let (output2, logApplied) = patchLoadedLogLevel(output, required = true)
  if not logApplied:
    quit(1)
  result = output2

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_enterprise_config_linux <path_to_index.js>"
    quit(1)
  let filePath = paramStr(1)
  echo "=== Patch: fix_enterprise_config_linux ==="
  echo "  Target: " & filePath
  if not fileExists(filePath):
    echo "  [FAIL] File not found: " & filePath
    quit(1)
  let input = readFile(filePath)
  let output = apply(input)
  if output != input:
    writeFile(filePath, output)
  echo "  [PASS] Enterprise config Linux support added"

  # Also patch index.pre.js if it exists (early bootstrap enterprise config).
  # Same refactored wrapper structure as index.js (best-effort, not required).
  let preJs = parentDir(filePath) / "index.pre.js"
  if fileExists(preJs):
    let preContent = readFile(preJs)
    let (afterWrapper, preApplied) =
      patchEnterpriseWrapper(preContent, required = false)
    # Promote the loaded-config log here too (best-effort; pre.js may differ).
    let (newPreContent, _) = patchLoadedLogLevel(afterWrapper, required = false)
    if newPreContent != preContent:
      writeFile(preJs, newPreContent)
      echo "  [OK] index.pre.js: enterprise config patched"
    elif preApplied:
      echo "  [OK] index.pre.js: enterprise config already patched"
