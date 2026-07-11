# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
#
# Local GrowthBook feature-flag overrides via <userData>/claude-desktop-bin.json.
#
# GrowthBook flags are served by Anthropic (/api/desktop/features) with no local
# override layer (the fcache disk cache is safeStorage-encrypted). This patch adds
# one: every load path (network fetch, disk cache, deployment-mode hardcoded set)
# funnels through a single features-store setter; we hook its head so a user's
# claude-desktop-bin.json (JSONC - comments allowed; auto-created template on
# first run) is merged over the freshly loaded map. Overrides are applied on a
# shallow copy, so the caller's raw payload (which feeds the disk cache) stays
# untouched. Layering: user override > server rollout.
#
# NOTE: flags that our patches force at the call site (enable_local_agent_mode
# etc. rewrite the read to !0) never consult the store, so this file cannot
# affect them - documented in the template and README.
#
# Sub-patches:
#   A: inject js/growthbook_overrides.js (defines globalThis.__cdbApplyGbOverrides)
#      after the first "use strict"; (runs before any chunk code)
#   B: hook the features-store setter: function X(e){const t=lf;lf=e,AP=!0;...
#      anchored on the stable log string "[growthbook] loaded %d features (%d changed)"
#
# Break risk: LOW - A uses the "use strict" anchor shared with custom_themes;
# B anchors on a log string that has been stable across releases. If upstream
# splits the setter or renames the log line, B fails loud.

import std/[os, strformat, strutils]
import std/nre

const OVERRIDES_JS = staticRead("../js/growthbook_overrides.js")
const EXPECTED_PATCHES = 2

proc apply*(input: string): string =
  result = input
  var patchesApplied = 0

  # --- Sub-patch A: helper injection ---------------------------------------
  if result.contains("__CDB_GB_OVERRIDES__"):
    echo "  [OK] growthbook overrides helper already present"
    inc patchesApplied
  else:
    const anchor = "\"use strict\";"
    let idx = result.find(anchor)
    if idx < 0:
      echo "  [FAIL] \"use strict\"; anchor not found"
    else:
      result =
        result[0 ..< idx + anchor.len] & OVERRIDES_JS & result[idx + anchor.len .. ^1]
      echo "  [OK] growthbook overrides helper injected after \"use strict\""
      inc patchesApplied

  # --- Sub-patch B: hook the features-store setter --------------------------
  # v1.19367.0 shape:
  #   function hTt(e){const t=lf;lf=e,AP=!0;const r=Object.keys(lf).length,
  #     n=Object.entries(lf).filter(...);v.info("[growthbook] loaded %d features (%d changed)",...)
  if result.contains("=(globalThis.__cdbApplyGbOverrides||"):
    echo "  [OK] features-store setter already hooked"
    inc patchesApplied
  else:
    let setterPat = nre.re(
      r"""(function [\w$]+\(([\w$]+)\)\{)(const [\w$]+=[\w$]+;[\w$]+=\2,[\w$]+=!0;const [\w$]+=Object\.keys\([\w$]+\)\.length[^"]{0,200}"\[growthbook\] loaded %d features \(%d changed\)")"""
    )
    var hooked = 0
    let m = result.find(setterPat)
    if m.isSome:
      let cap = m.get.captures
      let head = cap[0]
      let param = cap[1]
      let body = cap[2]
      let hook =
        head & param & "=(globalThis.__cdbApplyGbOverrides||function(x){return x})(" &
        param & ");" & body
      result = result.replace(m.get.match, hook)
      hooked = 1
    if hooked == 1:
      echo "  [OK] features-store setter hooked (overrides applied on every flag load)"
      inc patchesApplied
    else:
      echo "  [FAIL] features-store setter pattern: 0 matches (loaded-features log line moved?)"

  if patchesApplied < EXPECTED_PATCHES:
    echo &"  [FAIL] Only {patchesApplied}/{EXPECTED_PATCHES} patches applied"
    quit(1)
  echo &"  [PASS] {patchesApplied}/{EXPECTED_PATCHES} growthbook override patches applied"

when isMainModule:
  if paramCount() != 1:
    echo "Usage: add_growthbook_overrides <index.js>"
    quit(1)
  let path = paramStr(1)
  echo "=== Patch: add_growthbook_overrides ==="
  echo &"  Target: {path}"
  let content = readFile(path)
  let patched = apply(content)
  if patched != content:
    writeFile(path, patched)
