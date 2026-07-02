# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
#
# Enable Code and Cowork features on Linux.
#
# Multi-part patch:
#   1  darwin/win32-gated feature functions (count varies per version: quietPenguin
#      always; chillingSlothFeat too in <=v1.10628.2, but in v1.11187.4 it moved to a
#      non-platform gate `oW`, leaving only quietPenguin here. Patch 3's merger
#      force-overrides all of them regardless, so this is belt-and-suspenders.)
#   1b yukonSilver (NH) Linux early return
#   2  chillingSlothLocal (no-op -- inherently supported on Linux)
#   3  mC() async merger overrides
#   3b coworkKappa GrowthBook flag 123929380
#   3c coworkArtifacts GrowthBook flag 2940196192
#   3d chillingSlothPool GrowthBook flag 1992087837
#   3e (removed upstream v1.17282.0: markTaskComplete flag 3732274605 no longer exists)
#   3f ENABLE_TOOL_SEARCH GrowthBook flag 1129419822
#   3g toolResultFormatting GrowthBook flag 2192324205
#   3h deterministicSorting GrowthBook flag 2800354941
#   3i pluginEnabledState GrowthBook flag 4274871493
#   3j claudePreview GrowthBook flag 2976814254
#   3k canLaunchCodeSession GrowthBook flag 2067027393
#   3l canSaveSkill GrowthBook flag 3246569822
#   3m suggestSkillsEnabled GrowthBook flag 245679952
#   3n (removed upstream v1.18286.0: sshRemotePassthrough flag 1496676413 no longer
#      exists - the SSH remote MCP/plugin passthrough went unconditional:
#      createSpawnFunction lost the flag argument and resolveSshControllerForMcp
#      now returns the controller whenever an sshConfig is present)
#   3o consolidateMemoryV2 GrowthBook flag 1824824999
#   3p coworkOnboarding GrowthBook flag 2114777685
#   4  preferences defaults (quietPenguinEnabled / louderPenguinEnabled)
#
# (Patches 5/5b/6/8 — the MSIX-era platform spoofs — were REMOVED 2026-07-01 for
# issue #173. They told claude.ai we were macOS in HTTP headers (5:
# anthropic-client-os-platform=darwin, 5b: Macintosh User-Agent) but Windows via
# IPC and the renderer main world (6: getSystemInfo platform=win32, 8:
# navigator.platform=Win32 + Windows userAgentFallback). The official Linux .deb
# reports "linux" natively and claude.ai supports Linux natively; the leftover
# spoofs made the renderer's client-side platform check see Windows, so its
# Cowork gate showed "Cowork is not currently supported on Windows" on Linux.
# There is also no patch 7 — a former vestigial mainView.js window.process.platform
# spoof, removed earlier; if one is ever genuinely needed again, add it to
# fix_process_argv_renderer.nim, which legitimately targets mainView.js.)
#
# This patch targets index.js only.

import std/[os, strformat, strutils]
import std/nre

const EXPECTED_PATCHES = 19

proc apply*(input: string): string =
  result = input
  var failed = false
  var patchesApplied = 0

  # Patch 1: Remove platform gate from every darwin/win32-gated feature function.
  # v1.8089+: gate changed from `process.platform!=="darwin"` to compound
  #   `process.platform!=="darwin"&&process.platform!=="win32"` — match both variants.
  # The number of matching functions varies per upstream release (2 through
  # v1.10628.2, 1 in v1.11187.4 after chillingSlothFeat moved to the `oW` gate),
  # so accept >=1 (see the matches.len branches below).
  let pattern1 =
    re"""(function )([\w$]+)(\(\)\{return )process\.platform!=="darwin"(?:&&process\.platform!=="win32")?\?\{status:"unavailable"\}:(\{status:"supported"\}\})"""

  var matches: seq[RegexMatch] = @[]
  var pos = 0
  while true:
    let m = result.find(pattern1, pos)
    if m.isNone:
      break
    matches.add(m.get())
    pos = m.get().matchBounds.b + 1

  if matches.len >= 2:
    # Patch both: reverse order to preserve byte offsets
    for i in countdown(matches.len - 1, 0):
      let m = matches[i]
      let replacement = m.captures[0] & m.captures[1] & m.captures[2] & m.captures[3]
      let bounds = m.matchBounds
      result = result[0 ..< bounds.a] & replacement & result[bounds.b + 1 .. ^1]
    echo &"  [OK] darwin/win32-gated functions ({matches[0].captures[1]} + {matches[1].captures[1]}): both patched"
    inc patchesApplied
  elif matches.len == 1:
    let m = matches[0]
    let replacement = m.captures[0] & m.captures[1] & m.captures[2] & m.captures[3]
    let bounds = m.matchBounds
    result = result[0 ..< bounds.a] & replacement & result[bounds.b + 1 .. ^1]
    echo &"  [OK] darwin-gated function ({matches[0].captures[1]}): 1 match"
    inc patchesApplied
  else:
    echo "  [FAIL] darwin-gated functions: 0 matches, expected at least 1"
    failed = true

  if failed:
    echo "  [FAIL] Required patterns did not match"
    quit(1)

  # Patch 1b: yukonSilver (Cowork) platform gate — now a REGRESSION GUARD.
  #
  # History of the gate this used to force:
  #   - <=v1.12603: `function NH(){const A=process.platform;if(A!=="darwin"&&
  #     A!=="win32")return{status:"unsupported",...}}` — explicit platform gate.
  #   - v1.13576: refactored to `yukonSilver:Zce()` delegating through a
  #     support-status helper that hardcoded `const A="win32"` and checked
  #     `fo.files["win32"][arch]` — so Linux yielded unsupported. We injected a
  #     `if(process.platform==="linux")return{status:"supported"}` early-return.
  #
  # The official Linux .deb UPSTREAMED native Cowork support. The chain is now:
  #     yukonSilver:Wge()
  #     function Wge(){const A=N6i();if(A)return A;if(ohA)return ohA;
  #       const e=_6i();if(e.status!=="supported")return are()?g9(e):e; ...secureVm...}
  #     function _6i(){return process.platform,S6i()}
  #     function S6i(){const A=process.arch;
  #       if(A!=="x64"&&A!=="arm64"||!eo.files[e_A("linux")][A])return{...unsupported_architecture};
  #       const e=are(); return e?(...check helperBinaryPath/smolBinPath/virtiofsdPath...):...}
  #     function e_A(A){switch(A){case"darwin":case"linux":return"unix";case"win32":return"win32";default:return null}}
  #     const eo={...files:{unix:{arm64:[{name:"rootfs.img",...}],x64:[...]}, ...}}
  # i.e. the support check is keyed on `e_A("linux")` -> "unix", a real VM-bundle
  # key (rootfs.img is shipped), and gated on the REAL KVM/helper capability probe
  # `are()`. So on Linux x64/arm64 with the bundle + KVM present, yukonSilver
  # natively reports supported — and correctly reports unsupported when KVM is
  # missing or the arch is unsupported.
  #
  # Forcing `{status:"supported"}` now would be HARMFUL: it would override
  # upstream's legitimate arch/KVM/bundle checks and claim Cowork works on a
  # KVM-less or wrong-arch host (runtime failure). So per CLAUDE.md Rule 6 we keep
  # this as a regression guard that POSITIVELY asserts the native Linux support
  # path exists (the linux->"unix" bundle-key mapper AND the support determiner
  # that indexes eo.files[e_A("linux")][arch]). If a future bump re-hardcodes the
  # gate to win32 / drops the linux mapper, this FAILs loud — Cowork would silently
  # vanish from Linux otherwise.
  let eAMapsLinux =
    re"""switch\([\w$]+\)\{case"darwin":case"linux":return"unix";case"win32":return"win32""""
  let supportIndexesLinux = re"""\.files\[[\w$]+\("linux"\)\]\[[\w$]+\]"""
  if result.find(eAMapsLinux).isSome and result.find(supportIndexesLinux).isSome:
    echo "  [OK] yukonSilver: native Linux Cowork support path present (linux->\"unix\" bundle key + eo.files[e_A(\"linux\")][arch], gated on are() KVM probe) — regression guard satisfied"
    inc patchesApplied
  else:
    echo "  [FAIL] yukonSilver: native Linux Cowork support path NOT found (e_A linux->unix mapper or eo.files[e_A(\"linux\")][arch] index missing) — upstream may have re-gated Cowork off Linux; re-audit Patch 1b"
    failed = true

  # Patch 2: chillingSlothLocal -- no gate needed
  echo "  [OK] chillingSlothLocal: no gate needed (naturally returns supported on Linux)"
  inc patchesApplied

  # Patch 3: Override features in mC() async merger.
  #
  # IMPORTANT: do NOT force-override the Cowork VM capability features
  # (yukonSilver / yukonSilverGems / coworkKappa / coworkArtifacts) here. Those
  # are gated by upstream's NATIVE VM-capability probe (`Wge()`/`are()`, which
  # checks /dev/kvm, OVMF firmware, qemu, virtiofsd and the bundled helper).
  # Patch 1b above is a regression guard that asserts the native Linux support
  # PATH exists; it deliberately forces nothing. Slamming yukonSilver to
  # "supported" here would MASK a real unavailable state (KVM-less host, missing
  # firmware/qemu), so the UI would advertise Cowork and then fail at VM spawn
  # with a generic error instead of the honest "install QEMU / add to kvm group"
  # message. Let the native determiner report true support. (This is the same
  # capability-masking failure mode as the deleted claude-native.js stub.)
  #
  # We DO override the features we genuinely provide the backend for on Linux:
  # Claude Code / dispatch (chillingSloth*), Computer Use (we ship the input +
  # screenshot backends), plugins (ccdPlugins), and the penguin prefs.
  let overrides =
    ",quietPenguin:{status:\"supported\"},louderPenguin:{status:\"supported\"},chillingSlothFeat:{status:\"supported\"},chillingSlothLocal:{status:\"supported\"},chillingSlothPool:{status:\"supported\"},ccdPlugins:{status:\"supported\"},computerUse:{status:\"supported\"}"

  # New format: return{...FUNC(),...props}}; or }},
  let pattern3New = re"(return\{\.\.\.(?:[\w$]+)\(\),[^}]+)(\}\}[;,])"
  let m3 = result.find(pattern3New)
  if m3.isSome:
    let bounds = m3.get().matchBounds
    let endChar = $result[bounds.b] # ';' or ','
    let endTag = "}}" & endChar
    let insertPos = bounds.b + 1 - endTag.len
    result = result[0 ..< insertPos] & overrides & endTag & result[bounds.b + 1 .. ^1]
    echo "  [OK] mC() feature merger: 7 features overridden (1 match)"
    inc patchesApplied
  else:
    # Fallback: old format
    let pattern3Old =
      re"(const [\w$]+=async\(\)=>\(\{\.\.\.[\w$]+\(\),[^}]+)(await [\w$]+\(\))\}\)"
    var count3 = 0
    result = result.replace(
      pattern3Old,
      proc(m: RegexMatch): string =
        inc count3
        if count3 > 1:
          return m.match
        m.captures[0] & m.captures[1] & overrides & "})",
    )
    if count3 >= 1:
      echo &"  [OK] mC() feature merger: 7 features overridden (old format, {count3} match)"
      inc patchesApplied
    else:
      echo "  [FAIL] mC() feature merger: 0 matches, expected 1"
      failed = true

  # Patch 3b: Enable coworkKappa GrowthBook flag (123929380) on Linux
  let kappaPattern = re"""[\w$]+\("123929380"\)"""
  var kappaApplied = 0
  result = result.replace(
    kappaPattern,
    proc(m: RegexMatch): string =
      inc kappaApplied
      "!0",
  )
  if kappaApplied >= 3:
    echo &"  [OK] coworkKappa flag 123929380: forced ON ({kappaApplied} matches)"
    inc patchesApplied
  elif kappaApplied > 0:
    echo &"  [FAIL] coworkKappa flag 123929380: only {kappaApplied}/3 matches"
    failed = true
  else:
    echo "  [FAIL] coworkKappa flag 123929380: 0 matches"
    failed = true

  # Patch 3c: Enable coworkArtifacts GrowthBook flag (2940196192) on Linux
  let artifactsPattern = re"""[\w$]+\("2940196192"\)"""
  var artifactsApplied = 0
  result = result.replace(
    artifactsPattern,
    proc(m: RegexMatch): string =
      inc artifactsApplied
      "!0",
  )
  if artifactsApplied >= 3:
    echo &"  [OK] coworkArtifacts flag 2940196192: forced ON ({artifactsApplied} matches)"
    inc patchesApplied
  elif artifactsApplied > 0:
    echo &"  [FAIL] coworkArtifacts flag 2940196192: only {artifactsApplied}/3 matches"
    failed = true
  else:
    echo "  [FAIL] coworkArtifacts flag 2940196192: 0 matches"
    failed = true

  # Patch 3d: Enable chillingSlothPool GrowthBook flag (1992087837) on Linux
  let poolPattern = re"""[\w$]+\("1992087837"\)"""
  var poolApplied = 0
  result = result.replace(
    poolPattern,
    proc(m: RegexMatch): string =
      inc poolApplied
      "!0",
  )
  if poolApplied >= 1:
    echo &"  [OK] chillingSlothPool flag 1992087837: forced ON ({poolApplied} matches)"
    inc patchesApplied
  else:
    echo "  [FAIL] chillingSlothPool flag 1992087837: 0 matches"
    failed = true

  # Patch 3e (markTaskComplete, GrowthBook flag 3732274605) was REMOVED upstream
  # in v1.17282.0 -- the feature no longer exists in the bundle (neither the numeric
  # id nor the `markTaskComplete` key appear anywhere). Sub-patch deleted accordingly;
  # EXPECTED_PATCHES dropped 24 -> 23 and the merger override list dropped to 11 keys.

  # Patch 3f: Enable ENABLE_TOOL_SEARCH for LAM sessions - flag 1129419822
  let toolSearchPattern = re"""[\w$]+\("1129419822"\)"""
  var toolSearchApplied = 0
  result = result.replace(
    toolSearchPattern,
    proc(m: RegexMatch): string =
      inc toolSearchApplied
      "!0",
  )
  if toolSearchApplied >= 1:
    echo &"  [OK] ENABLE_TOOL_SEARCH flag 1129419822: forced ON ({toolSearchApplied} matches)"
    inc patchesApplied
  else:
    echo "  [FAIL] ENABLE_TOOL_SEARCH flag 1129419822: 0 matches"
    failed = true

  # Patch 3g: Enable tool use result formatting - flag 2192324205
  let toolResultFmtPattern = re"""[\w$]+\("2192324205"\)"""
  var toolResultFmtApplied = 0
  result = result.replace(
    toolResultFmtPattern,
    proc(m: RegexMatch): string =
      inc toolResultFmtApplied
      "!0",
  )
  if toolResultFmtApplied >= 1:
    echo &"  [OK] toolResultFormatting flag 2192324205: forced ON ({toolResultFmtApplied} matches)"
    inc patchesApplied
  else:
    echo "  [FAIL] toolResultFormatting flag 2192324205: 0 matches"
    failed = true

  # Patch 3h: Enable deterministic sorting of plugins/tools/logs - flag 2800354941
  let detSortPattern = re"""[\w$]+\("2800354941"\)"""
  var detSortApplied = 0
  result = result.replace(
    detSortPattern,
    proc(m: RegexMatch): string =
      inc detSortApplied
      "!0",
  )
  if detSortApplied >= 1:
    echo &"  [OK] deterministicSorting flag 2800354941: forced ON ({detSortApplied} matches)"
    inc patchesApplied
  else:
    echo "  [FAIL] deterministicSorting flag 2800354941: 0 matches"
    failed = true

  # Patch 3i: Enable plugin enabled state fetching - flag 4274871493
  let pluginStatePattern = re"""[\w$]+\("4274871493"\)"""
  var pluginStateApplied = 0
  result = result.replace(
    pluginStatePattern,
    proc(m: RegexMatch): string =
      inc pluginStateApplied
      "!0",
  )
  if pluginStateApplied >= 1:
    echo &"  [OK] pluginEnabledState flag 4274871493: forced ON ({pluginStateApplied} matches)"
    inc patchesApplied
  else:
    echo "  [FAIL] pluginEnabledState flag 4274871493: 0 matches"
    failed = true

  # Patch 3j: Enable Claude Preview dev server manager - flag 2976814254
  let previewPattern = re"""[\w$]+\("2976814254"\)"""
  var previewApplied = 0
  result = result.replace(
    previewPattern,
    proc(m: RegexMatch): string =
      inc previewApplied
      "!0",
  )
  if previewApplied >= 1:
    echo &"  [OK] claudePreview flag 2976814254: forced ON ({previewApplied} matches)"
    inc patchesApplied
  else:
    echo "  [FAIL] claudePreview flag 2976814254: 0 matches"
    failed = true

  # Patch 3k: Enable canLaunchCodeSession suggestion tool - flag 2067027393
  let launchCodePattern = re"""[\w$]+\("2067027393"\)"""
  var launchCodeApplied = 0
  result = result.replace(
    launchCodePattern,
    proc(m: RegexMatch): string =
      inc launchCodeApplied
      "!0",
  )
  if launchCodeApplied >= 1:
    echo &"  [OK] canLaunchCodeSession flag 2067027393: forced ON ({launchCodeApplied} matches)"
    inc patchesApplied
  else:
    echo "  [FAIL] canLaunchCodeSession flag 2067027393: 0 matches"
    failed = true

  # Patch 3l: Enable canSaveSkill - flag 3246569822
  let saveSkillPattern = re"""[\w$]+\("3246569822"\)"""
  var saveSkillApplied = 0
  result = result.replace(
    saveSkillPattern,
    proc(m: RegexMatch): string =
      inc saveSkillApplied
      "!0",
  )
  if saveSkillApplied >= 1:
    echo &"  [OK] canSaveSkill flag 3246569822: forced ON ({saveSkillApplied} matches)"
    inc patchesApplied
  else:
    echo "  [FAIL] canSaveSkill flag 3246569822: 0 matches"
    failed = true

  # Patch 3m: Enable suggestSkillsEnabled - flag 245679952
  let suggestSkillsPattern = re"""[\w$]+\("245679952"\)"""
  var suggestSkillsApplied = 0
  result = result.replace(
    suggestSkillsPattern,
    proc(m: RegexMatch): string =
      inc suggestSkillsApplied
      "!0",
  )
  if suggestSkillsApplied >= 1:
    echo &"  [OK] suggestSkillsEnabled flag 245679952: forced ON ({suggestSkillsApplied} matches)"
    inc patchesApplied
  else:
    echo "  [FAIL] suggestSkillsEnabled flag 245679952: 0 matches"
    failed = true

  # Patch 3n removed (upstream v1.18286.0): sshRemotePassthrough flag 1496676413
  # was deleted upstream and the SSH passthrough went unconditional. Guard against
  # the flag silently returning (which would re-gate the feature OFF for us).
  if "\"1496676413\"" in result:
    echo "  [FAIL] sshRemotePassthrough flag 1496676413 reappeared - re-add Patch 3n"
    failed = true

  # Patch 3o: Enable consolidate-memory skill v2 - flag 1824824999
  let memorySkillPattern = re"""[\w$]+\("1824824999"\)"""
  var memorySkillApplied = 0
  result = result.replace(
    memorySkillPattern,
    proc(m: RegexMatch): string =
      inc memorySkillApplied
      "!0",
  )
  if memorySkillApplied >= 1:
    echo &"  [OK] consolidateMemoryV2 flag 1824824999: forced ON ({memorySkillApplied} matches)"
    inc patchesApplied
  else:
    echo "  [FAIL] consolidateMemoryV2 flag 1824824999: 0 matches"
    failed = true

  # Patch 3p: Enable cowork onboarding role picker - flag 2114777685
  let onboardingPattern = re"""[\w$]+\("2114777685"\)"""
  var onboardingApplied = 0
  result = result.replace(
    onboardingPattern,
    proc(m: RegexMatch): string =
      inc onboardingApplied
      "!0",
  )
  if onboardingApplied >= 1:
    echo &"  [OK] coworkOnboarding flag 2114777685: forced ON ({onboardingApplied} matches)"
    inc patchesApplied
  else:
    echo "  [FAIL] coworkOnboarding flag 2114777685: 0 matches"
    failed = true

  # Patch 4: Change preferences defaults for Code features
  let pattern4Old = "quietPenguinEnabled:!1,louderPenguinEnabled:!1"
  let pattern4New = "quietPenguinEnabled:!0,louderPenguinEnabled:!0"
  var count4 = result.count(pattern4Old)
  if count4 >= 1:
    result = result.replace(pattern4Old, pattern4New)
    echo &"  [OK] Preferences defaults: quietPenguinEnabled + louderPenguinEnabled -> true ({count4} match)"
    inc patchesApplied
  else:
    echo "  [FAIL] Preferences defaults: 0 matches for quietPenguinEnabled/louderPenguinEnabled"
    failed = true

  if failed:
    echo "  [FAIL] Required patterns did not match"
    quit(1)

  # Guard for the removed platform spoofs (5/6): the real platform must reach
  # claude.ai unspoofed. Assert the header builder still sends the raw
  # `.platform` read (so a stale pre-built binary or a merge resurrection of the
  # spoof fails loud), per CLAUDE.md Rule 6 (positive end-state assertion).
  let headerUnspoofed = re"""\["anthropic-client-os-platform",[\w$]+\.platform\]"""
  if result.find(headerUnspoofed).isSome:
    echo "  [OK] platform reporting: anthropic-client-os-platform sends the real platform (spoofs removed for issue #173)"
    inc patchesApplied
  elif "anthropic-client-os-platform" notin result:
    echo "  [FAIL] platform reporting: anthropic-client-os-platform header GONE — upstream refactored the header builder; re-audit"
    quit(1)
  else:
    echo "  [FAIL] platform reporting: anthropic-client-os-platform header present but not the raw `.platform` read — a spoof or refactor is in place; re-audit"
    quit(1)

  # Write back if changed
  if result != input:
    echo "  [PASS] Code + Cowork features enabled in index.js"
  else:
    echo "  [WARN] No changes made to index.js (patterns may have already been applied)"

when isMainModule:
  if paramCount() != 1:
    echo "Usage: enable_local_agent_mode <path_to_index.js>"
    quit(1)

  let filePath = paramStr(1)
  echo "=== Patch: enable_local_agent_mode ==="
  echo "  Target: " & filePath

  if not fileExists(filePath):
    echo "  [FAIL] File not found: " & filePath
    quit(1)

  var input = readFile(filePath)
  var output = apply(input)

  # Former Patch 8 (navigator.platform=Win32 + Windows userAgentFallback in the
  # renderer main world) was removed for issue #173. Assert the spoof is really
  # gone from the output — its marker resurfacing would mean a stale pre-patched
  # input or a bad merge, and would break Cowork on Linux again.
  if "__nav_spoof_applied" in output:
    echo "  [FAIL] navigator spoof marker (__nav_spoof_applied) still present — input was patched by an old build; use a fresh upstream extract"
    quit(1)

  if output != input:
    writeFile(filePath, output)

  echo &"  [PASS] {EXPECTED_PATCHES}/{EXPECTED_PATCHES} patches applied"
