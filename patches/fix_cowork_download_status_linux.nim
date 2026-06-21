# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
#
# Suppress the false "Download a one-time package" agent-mode banner and skip
# automatic VM provisioning on Linux (native Cowork backend).
#
# NOTE: this is NOT 3p/enterprise.json specific. It is gated purely on Linux +
# native backend and applies equally to 1p (personal) and 3p (managed/gateway)
# deployments. (It was first observed in a gateway enterprise.json setup, but a
# plain 1p Linux user on the native backend hits the identical false banner.)
#
# Background
# ----------
# Claude Desktop's Cowork/agent-mode UI shows a banner — "Get set up for agent
# mode. Download a one-time package to give Claude a secure workspace on your
# computer." — whenever it believes the sandbox VM image is not installed. The
# banner copy itself lives in the remote claude.ai web bundle, but the *status it
# reacts to* is decided locally in this (main-process) bundle by:
#
#     getDownloadStatus(){return xX()?eN.Downloading:p5()?eN.Ready:eN.NotDownloaded}
#
# where `p5()` checks the filesystem for the VM bundle (`claudevm.bundle` ->
# `rootfs.vhdx`/`rootfs.qcow2`) under app userData. On macOS/Windows the VM image
# genuinely must be downloaded; on Linux it does NOT — Cowork runs the `claude`
# CLI on the host via claude-cowork-service over a Unix socket (native backend),
# so there is no VM image and `p5()` always returns false -> `NotDownloaded` ->
# the banner shows even though Cowork works perfectly. (Verified end-to-end:
# sessions spawn natively and `Turn succeeded` while the banner is on screen.)
#
# Native vs KVM
# -------------
# claude-cowork-service has two backends. In **native** mode there is no VM image
# (banner is false). In **KVM** mode it boots Anthropic's guest image and the
# image genuinely must be present — there the banner is CORRECT and must NOT be
# suppressed. The backend is not exposed to Desktop via process.env
# (COWORK_VM_BACKEND is the daemon's env, not Desktop's), but the cowork mode
# preamble (js/cowork_mode_preamble.js, injected at "use strict";) sets
# `globalThis.__coworkKvmMode` from socket auto-detection. Existing patches
# already gate on it (fix_cowork_linux.nim). We do the same: only short-circuit
# in Linux + native (`!globalThis.__coworkKvmMode`); Linux-KVM and win/mac fall
# through to the original `p5()` check unchanged.
#
# Patches
# -------
# 1. Rewrite getDownloadStatus so that on Linux native it returns the enum's
# Ready value; otherwise the original expression is preserved byte-for-byte:
#
#     getDownloadStatus(){return process.platform==="linux"&&!globalThis.__coworkKvmMode
#       ? <enumVar>.Ready
#       : xX()?<enumVar>.Downloading:p5()?<enumVar>.Ready:<enumVar>.NotDownloaded}
#
# 2. Make the public download() entry point return success without provisioning
# in Linux native mode. The renderer invokes this independently of the status.
#
# 3. Keep setYukonSilverConfig's config update, then return before its
# autoDownloadInBackground refresh in Linux native mode. The original refresh
# expression remains unchanged for Linux KVM, Windows, and macOS:
#
#     setYukonSilverConfig(config) {
#       updateConfig(config);
#       if (process.platform === "linux" && !globalThis.__coworkKvmMode) return;
#       config.autoDownloadInBackground && ...
#     }
#
# The enum var (`eN` in v1.13576.4) and the check fns (`xX`/`p5`) are minified
# and churn every release, so we capture them with `[\w$]+` and a backreference
# (std/nre) instead of hardcoding. This pairs with enable_local_agent_mode.nim's
# `yukonSilver:{status:"supported"}` feature gate ("Cowork is allowed"); this one
# is the runtime-status complement ("the local agent-mode package is present").

import std/os
import std/nre

const EXPECTED_PATCHES = 3

const LINUX_NATIVE_CONDITION =
  """process.platform==="linux"&&!globalThis.__coworkKvmMode"""

proc apply*(input: string): string =
  result = input
  var patchesApplied = 0

  # Patch 1: report Ready without looking for a VM bundle in Linux native mode.
  let statusDonePat =
    re"""getDownloadStatus\(\)\{return process\.platform==="linux"&&!globalThis\.__coworkKvmMode\?[\w$]+\.Ready:"""
  if result.find(statusDonePat).isSome:
    echo "  [OK] getDownloadStatus Linux-native short-circuit present"
    inc patchesApplied
  else:
    let statusPattern =
      re"""(getDownloadStatus\(\)\{return )([\w$]+\(\)\?([\w$]+)\.Downloading:[\w$]+\(\)\?\3\.Ready:\3\.NotDownloaded)\}"""
    var statusCount = 0
    result = result.replace(
      statusPattern,
      proc(m: RegexMatch): string =
        inc statusCount
        if statusCount > 1:
          return m.match
        let prefix = m.captures[0]
        let origExpr = m.captures[1]
        let enumVar = m.captures[2]
        prefix & LINUX_NATIVE_CONDITION & "?" & enumVar & ".Ready:" &
          origExpr & "}",
    )
    if statusCount == 1:
      echo "  [OK] getDownloadStatus Linux-native short-circuit: 1 match"
      inc patchesApplied
    else:
      echo "  [FAIL] getDownloadStatus method not found uniquely " &
        "(expected `getDownloadStatus(){return ...?...Downloading:...?...Ready:...NotDownloaded}`)"

  # Patch 2: the renderer may call download() even after observing Ready. Treat
  # that request as already satisfied in native mode.
  let downloadDonePat =
    re"""async download\(\)\{if\(process\.platform==="linux"&&!globalThis\.__coworkKvmMode\)return\{success:!0\};try\{return await [\w$]+\(\),\{success:[\w$]+\(\)\}\}"""
  if result.find(downloadDonePat).isSome:
    echo "  [OK] download Linux-native provisioning guard present"
    inc patchesApplied
  else:
    let downloadPattern =
      re"""(async download\(\)\{)(try\{return await [\w$]+\(\),\{success:[\w$]+\(\)\}\})"""
    var downloadCount = 0
    result = result.replace(
      downloadPattern,
      proc(m: RegexMatch): string =
        inc downloadCount
        if downloadCount > 1:
          return m.match
        m.captures[0] & "if(" & LINUX_NATIVE_CONDITION &
          ")return{success:!0};" & m.captures[1],
    )
    if downloadCount == 1:
      echo "  [OK] download Linux-native provisioning guard: 1 match"
      inc patchesApplied
    else:
      echo "  [FAIL] public VM download entry point not found uniquely"

  # Patch 3: retain the config update, but do not provision a VM bundle when
  # the native service is the selected Linux backend.
  let provisioningDonePat =
    re"""setYukonSilverConfig\(([\w$]+)\)\{[\w$]+\(\1\);if\(process\.platform==="linux"&&!globalThis\.__coworkKvmMode\)return;\1\.autoDownloadInBackground&&"""
  if result.find(provisioningDonePat).isSome:
    echo "  [OK] setYukonSilverConfig Linux-native provisioning guard present"
    inc patchesApplied
  else:
    let provisioningPattern =
      re"""(setYukonSilverConfig\(([\w$]+)\)\{[\w$]+\(\2\)),(\2\.autoDownloadInBackground&&)"""
    var provisioningCount = 0
    result = result.replace(
      provisioningPattern,
      proc(m: RegexMatch): string =
        inc provisioningCount
        if provisioningCount > 1:
          return m.match
        let configUpdate = m.captures[0]
        let autoDownloadExpr = m.captures[2]
        configUpdate & ";if(" & LINUX_NATIVE_CONDITION & ")return;" &
          autoDownloadExpr,
    )
    if provisioningCount == 1:
      echo "  [OK] setYukonSilverConfig Linux-native provisioning guard: 1 match"
      inc patchesApplied
    else:
      echo "  [FAIL] setYukonSilverConfig auto-download path not found uniquely"

  if patchesApplied < EXPECTED_PATCHES:
    echo "  [FAIL] Only " & $patchesApplied & "/" & $EXPECTED_PATCHES &
      " patches applied"
    quit(1)

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_cowork_download_status_linux <path_to_index.js>"
    quit(1)
  let filePath = paramStr(1)
  echo "=== Patch: fix_cowork_download_status_linux ==="
  echo "  Target: " & filePath
  if not fileExists(filePath):
    echo "  [FAIL] File not found: " & filePath
    quit(1)
  let input = readFile(filePath)
  let output = apply(input)
  if output != input:
    writeFile(filePath, output)
  echo "  [PASS] Cowork download-status Linux-native short-circuit applied"
