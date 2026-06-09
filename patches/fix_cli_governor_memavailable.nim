# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
#
# Fix CliGovernor false memory-pressure warnings on Linux (#128).
#
# The governor polls cfg.getFreeMemoryRatio() every 10s (pollIntervalMs??1e4)
# and logs "[CliGovernor] memory pressure (warning|critical)" below 5%/2%
# (M$r=.05 / N$r=.02 in v1.11847.5), then may evict idle CLI sessions.
# Upstream computes the ratio from process.getSystemMemoryInfo().free, which
# on Linux is MemFree -- it excludes reclaimable page cache, so a healthy box
# reports ~5% "free" and the governor spams warnings. macOS uses native
# pressure events and never reaches this polling path.
#
# Fix: read MemAvailable/MemTotal from /proc/meminfo (the kernel's actual
# availability estimate). The original upstream expression is re-emitted
# verbatim after the try/catch as the fallback if the /proc read fails.

import std/[os, strutils]
import regex

# Injected at the top of the lambda body, before the original code.
# mi/av/to are try-block-scoped so they cannot clash with the original
# `var i;const t=...` that follows the catch. require("fs") hits Node's
# module cache after the first call. Math.min clamps the rare case where
# the MemAvailable estimate exceeds MemTotal. Both values are kB.
const MeminfoProbe =
  """try{const mi=require("fs").readFileSync("/proc/meminfo","utf8"),av=/MemAvailable:\s*(\d+)/.exec(mi),to=/MemTotal:\s*(\d+)/.exec(mi);if(av&&to&&+to[1]>0)return Math.min(1,+av[1]/+to[1])}catch{}"""

proc apply*(input: string): string =
  # Idempotency: the fresh v1.11847.5 bundle has zero occurrences of
  # "/proc/meminfo"; finding it shortly after "getFreeMemoryRatio:" means
  # this patch is already in place.
  let anchor = input.find("getFreeMemoryRatio:")
  if anchor >= 0 and "/proc/meminfo" in input[anchor ..< min(anchor + 200, input.len)]:
    echo "  [OK] CliGovernor MemAvailable ratio: already applied"
    return input

  # Matches the definition site only (v1.11847.5, exactly 1 occurrence;
  # the call site `this.cfg.getFreeMemoryRatio(),` has no `:()=>`):
  #   getFreeMemoryRatio:()=>{var i;const t=(i=process.getSystemMemoryInfo)==null?void 0:i.call(process);return t&&t.total>0?t.free/t.total:1}
  # Group 0 captures the entire original body so it can be re-emitted as
  # the fallback path without hardcoding the minified identifiers (i, t).
  let pattern =
    re2"""getFreeMemoryRatio:\(\)=>\{(var [\w$]+;const [\w$]+=\([\w$]+=process\.getSystemMemoryInfo\)==null\?void 0:[\w$]+\.call\(process\);return [\w$]+&&[\w$]+\.total>0\?[\w$]+\.free/[\w$]+\.total:1)\}"""
  var count = 0
  result = input.replace(
    pattern,
    proc(m: RegexMatch2, s: string): string =
      inc count
      "getFreeMemoryRatio:()=>{" & MeminfoProbe & s[m.group(0)] & "}",
  )
  if count == 0:
    if "getFreeMemoryRatio" in input:
      echo "  [INFO] Found 'getFreeMemoryRatio' in file but pattern didn't match"
    echo "  [FAIL] CliGovernor getFreeMemoryRatio pattern: 0 matches (may need pattern update)"
    quit(1)
  echo "  [OK] CliGovernor MemAvailable ratio: " & $count & " match(es)"

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_cli_governor_memavailable <file>"
    quit(1)
  let filePath = paramStr(1)
  echo "=== Patch: fix_cli_governor_memavailable ==="
  echo "  Target: " & filePath
  let input = readFile(filePath)
  let output = apply(input)
  writeFile(filePath, output)
  echo "  [PASS] CliGovernor memory metric patched successfully"
