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

# The parsed JSON MUST be routed through the upstream key-registration function
# (`Hzi` in v1.15200's index.js) rather than returned raw. That function registers
# each config key into a module-scoped Set and validates the values (`AI(...)`).
# On Windows the Set is populated by walking the registry; our Linux reader bypasses
# that walk, so without calling it the Set stays empty and any managed/3p gate that
# reads it evaluates false. (This is exactly what broke 3p activation in the
# bootstrap — see fix_enterprise_config_linux_pre.nim.) We build the reader with the
# captured fn name substituted in.
proc linuxReader(kwFn: string): string =
  "(()=>{try{return " & kwFn &
    "(JSON.parse(require(\"fs\").readFileSync(\"/etc/claude-desktop/enterprise.json\",\"utf8\")))}catch(e){return{}}})()"

# v1.13576.0: upstream collapsed the darwin/win32 ternary
#     process.platform==="darwin"?FUNC_D():process.platform==="win32"?FUNC_W():{}
# into a single wrapper that unconditionally calls the win32 registry
# reader (the mac plist reader was removed):
#     function Mei(){const A=Rei();return Object.keys(A).length>0?A:void 0}
# where Rei() reads `SOFTWARE\Policies\...` and yields {} off-Windows.
#
# We patch that wrapper so on Linux it reads /etc/claude-desktop/enterprise.json
# (routed through the key-registration fn) instead of the (empty) registry result:
#     function Mei(){const A=process.platform==="linux"?(...kW(JSON.parse(...))...):Rei();return ...}
#
# The wrapper is anchored on the registry-reader fn, whose name we capture from its
# `SOFTWARE\Policies` body so we don't hardcode a minified name. index.pre.js (the
# early bootstrap) has the same structure but is patched by the separate
# fix_enterprise_config_linux_pre.nim (the orchestrator stages each target in
# isolation, so a sibling patch here would be a silent no-op).
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
    return (input, false)
  let regFn = input[regMatch.group(0)]

  # Capture the key-registration fn (Hzi): registers config keys into the gate Set
  # and validates. Shape: function N(t){for(const e of Object.keys(t)){const r=
  # <map>.get(e);r!==void 0&&<set>.add(r)}return ...}
  let kwFnPat = re2(
    """function ([\w$]+)\([\w$]+\)\{for\(const [\w$]+ of Object\.keys\([\w$]+\)\)\{const [\w$]+=[\w$]+\.get\([\w$]+\);[\w$]+!==void 0&&[\w$]+\.add\([\w$]+\)\}"""
  )
  var kwMatch: RegexMatch2
  if not input.find(kwFnPat, kwMatch):
    if required:
      echo "  [FAIL] Could not locate key-registration fn (populates the managed/3p gate set)"
    return (input, false)
  # regex2 group(0) is the FIRST capture group (not the whole match) — the fn name.
  let kwFn = input[kwMatch.group(0)]

  # Patch the enterprise wrapper that calls the registry reader:
  #   function X(){const Y=<regFn>();return Object.keys(Y).length>0?Y:void 0}
  let pattern = re2(
    """(function [\w$]+\(\)\{const [\w$]+=)(""" & regFn &
      """\(\);return Object\.keys\([\w$]+\)\.length>0)"""
  )
  var count = 0
  let reader = linuxReader(kwFn)
  let output = input.replace(
    pattern,
    proc(m: RegexMatch2, s: string): string =
      inc count
      # const Y= -> const Y=process.platform==="linux"?(...routed through kW...):
      s[m.group(0)] & """process.platform==="linux"?""" & reader & ":" & s[m.group(1)],
  )
  if count >= 1:
    echo "  [OK] Enterprise config Linux reader (via " & kwFn & "): " & $count &
      " match(es)"
    return (output, true)
  else:
    if required:
      echo "  [FAIL] Enterprise config wrapper not found (calls " & regFn & "())"
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

  # index.pre.js (the early bootstrap that gates the 3p-mode `-3p` userData split)
  # is patched by the SEPARATE patch fix_enterprise_config_linux_pre.nim, which the
  # orchestrator runs against the staged index.pre.js as its own target. It is NOT
  # patched here: the orchestrator stages each target file into an isolated tmpfs
  # copy, so index.pre.js is never a sibling of the staged index.js — a sibling
  # patch attempt here is a guaranteed no-op (this is the exact mechanism that
  # shipped v1.15200.0 half-patched).
