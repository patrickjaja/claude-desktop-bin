# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
#
# Log silently-suppressed main-webview renderer deaths (#128).
#
# The main webview's "render-process-gone" handler early-returns with NO
# log and NO reload when the expected-kill counter is >0 or the reason is
# "killed"/"clean-exit". A Linux kernel OOM SIGKILL surfaces as
# reason==="killed", so an OOM-killed renderer (-> blank view, claude.ai
# re-login) leaves no trace in main.log. Insert a logger call inside the
# early-return branch so suppressed deaths become visible. Pure
# observability -- the branch still decrements the counter and returns
# without reloading, exactly as before.

import std/[os, strutils]
import regex

# Literal substring of the injected log line; absent from the fresh bundle.
const AppliedMarker = "Main webview render process gone (suppressed)"

proc apply*(input: string): string =
  if AppliedMarker in input:
    echo "  [OK] suppressed renderer-gone log: already applied"
    return input

  # Matches (v1.11847.5, exactly 1 occurrence):
  #   .on("render-process-gone",async(i,r)=>{if(KG>0||r.reason==="killed"||r.reason==="clean-exit"){KG>0&&KG--;return}if(D.info("Main webview render process gone: %o
  # The trailing `.info("Main webview render process gone: %o` both pins
  # this site (8 render-process-gone registrations exist; only this one
  # logs that message) and captures the logger identifier.
  # Count policy: require >= 1 and echo the actual count -- the insertion
  # is correct for N copies of the registration, while 0 matches means
  # upstream changed the code and the patch must fail loudly.
  let pattern =
    re2"""\.on\("render-process-gone",async\(([\w$]+),([\w$]+)\)=>\{if\(([\w$]+)>0\|\|([\w$]+)\.reason==="killed"\|\|([\w$]+)\.reason==="clean-exit"\)\{([\w$]+)>0&&([\w$]+)--;return\}if\(([\w$]+)\.info\("Main webview render process gone: %o"""
  var count = 0
  result = input.replace(
    pattern,
    proc(m: RegexMatch2, s: string): string =
      inc count
      let evtParam = s[m.group(0)] # event arg (unused, re-emitted)
      let details = s[m.group(1)] # RenderProcessGoneDetails
      let counterA = s[m.group(2)] # expected-kill counter (1st occ)
      let detailsB = s[m.group(3)]
      let detailsC = s[m.group(4)]
      let counterB = s[m.group(5)]
      let counterC = s[m.group(6)] # the decrement
      let logger = s[m.group(7)] # module-level logger
      # expectedKills is logged BEFORE the decrement: >0 documents an
      # app-initiated kill; 0 with reason "killed" indicates an external
      # kill (e.g. kernel OOM).
      let injected =
        logger & """.info("Main webview render process gone (suppressed): %o",{reason:""" &
        details & ".reason,exitCode:" & details & ".exitCode,expectedKills:" & counterA &
        "})"
      """.on("render-process-gone",async(""" & evtParam & "," & details & ")=>{if(" &
        counterA & ">0||" & detailsB & """.reason==="killed"||""" & detailsC &
        """.reason==="clean-exit"){""" & injected & ";" & counterB & ">0&&" & counterC &
        "--;return}if(" & logger & """.info("Main webview render process gone: %o""",
  )
  if count == 0:
    if "Main webview render process gone" in input:
      echo "  [INFO] Found 'Main webview render process gone' in file but pattern didn't match"
    echo "  [FAIL] suppressed renderer-gone pattern: 0 matches (may need pattern update)"
    quit(1)
  echo "  [OK] suppressed renderer-gone log: " & $count & " match(es)"

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_renderer_gone_suppressed_log <file>"
    quit(1)
  let filePath = paramStr(1)
  echo "=== Patch: fix_renderer_gone_suppressed_log ==="
  echo "  Target: " & filePath
  let input = readFile(filePath)
  let output = apply(input)
  writeFile(filePath, output)
  echo "  [PASS] Suppressed renderer-gone log patched successfully"
