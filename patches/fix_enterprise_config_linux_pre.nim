# @patch-target: app.asar.contents/.vite/build/index.pre.js
# @patch-type: nim
#
# Enable enterprise config on Linux in the EARLY BOOTSTRAP bundle (index.pre.js).
#
# This is the sibling of fix_enterprise_config_linux.nim (which patches index.js,
# the main process). index.pre.js runs before the main process and is the file
# that decides whether the app enters 3p / enterprise / inference-gateway mode:
# it reads the managed config and, if present, relocates Electron userData to
# `~/.config/Claude-3p` (the `-3p` suffix). If the bootstrap can't see the Linux
# enterprise config, the app boots in 1p mode regardless of what index.js does
# later — inference falls back to api.anthropic.com and the gateway is bypassed.
#
# Upstream reads managed config via a win32-registry/macOS-plist reader; on Linux
# that returns {}. We splice in a /etc/claude-desktop/enterprise.json reader, the
# same way fix_enterprise_config_linux does for index.js.
#
# Why a SEPARATE patch file instead of patching index.pre.js inside the index.js
# patch: the orchestrator (scripts/apply_patches.py) stages each @patch-target into
# an isolated tmpfs copy and runs the binary against THAT copy, so index.pre.js is
# never a sibling of the staged index.js on disk. The old "also patch the sibling
# index.pre.js" block in fix_enterprise_config_linux.nim was therefore a guaranteed
# no-op through the build — which is exactly how v1.15200.0 shipped with the main
# process reading enterprise.json but 3p mode never activating. Making index.pre.js
# its own target routes it through normal staging and lets it be properly required.
#
# The wrapper structure matches index.js: a registry-reader fn whose body contains
# `SOFTWARE\Policies`, called by a one-line wrapper
#     function HW(){const t=xW();return Object.keys(t).length>0?t:void 0}
# We capture the reader fn name from its body (don't hardcode the minified name).

import std/[os, strutils]
import regex

# The parsed JSON MUST be routed through the upstream key-registration function
# (`kW` in v1.15200) rather than returned raw. That function does two things the
# 3p path depends on:
#   1. for each config key, `<keyMap>.get(key)` and `<gateSet>.add(...)` — it
#      populates the module-scoped Set that the bootstrap's managed/3p gate reads
#      (`r=[...<gateSet>].some(d=>!<seen>.has(d))`). On Windows this Set is filled
#      by walking the registry; our Linux reader bypasses that walk, so without
#      calling kW() the Set stays empty -> gate is false -> 3p NEVER activates
#      (app stays in ~/.config/Claude, inference falls back to api.anthropic.com).
#   2. validates/normalizes via `AI(...)`, matching Windows behavior.
# kW is in the same module scope as the wrapper, so the injected code can call it.
# We build the reader template with the captured kW name substituted in.
proc linuxReader(kwFn: string): string =
  "(()=>{try{return " & kwFn &
    "(JSON.parse(require(\"fs\").readFileSync(\"/etc/claude-desktop/enterprise.json\",\"utf8\")))}catch(e){return{}}})()"

proc apply*(input: string): string =
  # Idempotent: positively assert the patched end-state (the injected reader) is
  # present, NOT merely that the old pattern is gone (CLAUDE.md Rule 6).
  if "/etc/claude-desktop/enterprise.json" in input:
    echo "  [OK] Already patched (enterprise.json path found)"
    return input

  let regFnPat =
    re2"""function ([\w$]+)\(\)\{var [\w$]+,[\w$]+;const [\w$]+=`SOFTWARE\\\\Policies"""
  var regMatch: RegexMatch2
  if not input.find(regFnPat, regMatch):
    echo "  [FAIL] Could not locate win32 registry reader (SOFTWARE\\Policies fn) in index.pre.js"
    quit(1)
  let regFn = input[regMatch.group(0)]

  # Capture the key-registration fn (kW): its body registers config keys into the
  # gate Set and validates. Shape: function N(t){for(const e of Object.keys(t)){
  # const r=<map>.get(e);r!==void 0&&<set>.add(r)}return ...}
  let kwFnPat = re2(
    """function ([\w$]+)\([\w$]+\)\{for\(const [\w$]+ of Object\.keys\([\w$]+\)\)\{const [\w$]+=[\w$]+\.get\([\w$]+\);[\w$]+!==void 0&&[\w$]+\.add\([\w$]+\)\}"""
  )
  var kwMatch: RegexMatch2
  if not input.find(kwFnPat, kwMatch):
    echo "  [FAIL] Could not locate key-registration fn (kW: populates the 3p gate set) in index.pre.js"
    quit(1)
  # regex2 group(0) is the FIRST capture group (not the whole match) — the fn name.
  let kwFn = input[kwMatch.group(0)]

  # function X(){const Y=<regFn>();return Object.keys(Y).length>0?Y:void 0}
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
    echo "  [OK] Enterprise config Linux reader (bootstrap, via " & kwFn & "): " & $count &
      " match(es)"
    return output
  else:
    echo "  [FAIL] Bootstrap enterprise wrapper not found (calls " & regFn & "())"
    quit(1)

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_enterprise_config_linux_pre <path_to_index.pre.js>"
    quit(1)
  let filePath = paramStr(1)
  echo "=== Patch: fix_enterprise_config_linux_pre ==="
  echo "  Target: " & filePath
  if not fileExists(filePath):
    echo "  [FAIL] File not found: " & filePath
    quit(1)
  let input = readFile(filePath)
  let output = apply(input)
  if output != input:
    writeFile(filePath, output)
  echo "  [PASS] Enterprise config Linux bootstrap support added"
