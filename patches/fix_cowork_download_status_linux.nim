# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
#
# Suppress the false "Download a one-time package" agent-mode banner on Linux
# (native Cowork backend).
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
# Patch
# -----
# Rewrite getDownloadStatus so that on Linux native it returns the enum's Ready
# value; otherwise the original expression is preserved byte-for-byte:
#
#     getDownloadStatus(){return process.platform==="linux"&&!globalThis.__coworkKvmMode
#       ? <enumVar>.Ready
#       : xX()?<enumVar>.Downloading:p5()?<enumVar>.Ready:<enumVar>.NotDownloaded}
#
# The enum var (`eN` in v1.13576.4) and the check fns (`xX`/`p5`) are minified
# and churn every release, so we capture them with `[\w$]+` and a backreference
# (std/nre) instead of hardcoding. This pairs with enable_local_agent_mode.nim's
# `yukonSilver:{status:"supported"}` feature gate ("Cowork is allowed"); this one
# is the runtime-status complement ("the local agent-mode package is present").

import std/os
import std/nre

const EXPECTED_PATCHES = 1

# Linux-native guard expression prepended inside getDownloadStatus.
const LINUX_NATIVE_GUARD =
  """process.platform==="linux"&&!globalThis.__coworkKvmMode?"""

proc apply*(input: string): string =
  result = input

  # Idempotency: assert the PATCHED END-STATE is present (CLAUDE.md Rule 6),
  # not merely that the old pattern is gone. The end-state is the Linux-native
  # guard returning <enumVar>.Ready at the top of getDownloadStatus.
  let donePat =
    re"""getDownloadStatus\(\)\{return process\.platform==="linux"&&!globalThis\.__coworkKvmMode\?[\w$]+\.Ready:"""
  if result.find(donePat).isSome:
    echo "  [OK] Already patched (Linux-native download-status short-circuit present)"
    return result

  # Match the unpatched method and capture:
  #   g1 = "getDownloadStatus(){return "   (literal prefix)
  #   g2 = the full original expression     (preserved for the fall-through)
  #   g3 = the enum var (e.g. eN)           (reused to build <enumVar>.Ready)
  # The backreference \3 ties the three enum references together so we only match
  # the genuine method shape.
  let pattern =
    re"""(getDownloadStatus\(\)\{return )([\w$]+\(\)\?([\w$]+)\.Downloading:[\w$]+\(\)\?\3\.Ready:\3\.NotDownloaded)\}"""

  var count = 0
  result = result.replace(
    pattern,
    proc(m: RegexMatch): string =
      inc count
      if count > 1:
        return m.match # never touch a second (unexpected) occurrence
      let prefix = m.captures[0]
      let origExpr = m.captures[1]
      let enumVar = m.captures[2]
      prefix & LINUX_NATIVE_GUARD & enumVar & ".Ready:" & origExpr & "}",
  )

  if count >= 1:
    echo "  [OK] getDownloadStatus Linux-native short-circuit: " & $count & " match"
  else:
    echo "  [FAIL] getDownloadStatus method not found " &
      "(expected `getDownloadStatus(){return ...?...Downloading:...?...Ready:...NotDownloaded}`)"
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
