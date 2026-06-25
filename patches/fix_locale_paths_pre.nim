# @patch-target: app.asar.contents/.vite/build/index.pre.js
# @patch-type: nim
#
# Locale-path patch for the EARLY BOOTSTRAP bundle (index.pre.js).
#
# Sibling of fix_locale_paths.nim (which patches index.js, the main process,
# redirecting process.resourcesPath -> a runtime app.getAppPath()-based locales
# path so locale files resolve on Linux for any install method).
#
# As of v1.15200.0 the bootstrap bundle does NOT reference process.resourcesPath
# at all (the locale resolution happens entirely in the main process). So in the
# current version this patch is a REGRESSION GUARD, not an active rewrite:
#   - If index.pre.js has no process.resourcesPath: assert that and pass (nothing
#     to do — the absence is the expected, correct state).
#   - If a future upstream version moves a process.resourcesPath reference into the
#     bootstrap, rewrite it the same way fix_locale_paths does AND succeed.
#
# Why a SEPARATE patch file rather than patching index.pre.js as a sibling inside
# fix_locale_paths.nim: the orchestrator (scripts/apply_patches.py) stages each
# @patch-target into an isolated tmpfs copy and runs the binary against THAT copy,
# so index.pre.js is never a sibling of the staged index.js on disk. The old
# `parentDir(filePath)/"index.pre.js"` block in fix_locale_paths.nim was therefore
# dead through the build (a guaranteed no-op) — the same mechanism that shipped the
# enterprise-config bootstrap patch broken in v1.15200.0. Making index.pre.js its
# own target routes it through normal staging.
#
# This guard's success path is a POSITIVE assertion (CLAUDE.md Rule 6): it either
# applied the rewrite (and the patched expression is present), or it positively
# confirmed there is no process.resourcesPath to rewrite. It never keys success off
# the mere absence of an old pattern without distinguishing "absent" from "missed".

import std/[os, strutils]

proc apply*(input: string): string =
  let oldResourcePath = "process.resourcesPath"
  let newResourcePath =
    """(require("path").dirname(require("electron").app.getAppPath())+"/locales")"""

  # Already rewritten? (positive end-state: the patched locales expression present)
  if """getAppPath())+"/locales"""" in input and oldResourcePath notin input:
    echo "  [OK] index.pre.js: locale path already patched (no raw resourcesPath)"
    return input

  let count = input.count(oldResourcePath)
  if count == 0:
    # Expected for v1.15200.0: bootstrap does not resolve locales. Positively
    # assert absence — this is the correct end-state, not a silent miss.
    echo "  [OK] index.pre.js: no process.resourcesPath in bootstrap (nothing to patch — expected)"
    return input

  # A resourcesPath reference exists in the bootstrap → rewrite it (future-proofing).
  result = input.replace(oldResourcePath, newResourcePath)
  echo "  [OK] index.pre.js: process.resourcesPath rewritten (" & $count & " match(es))"

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_locale_paths_pre <path_to_index.pre.js>"
    quit(1)
  let filePath = paramStr(1)
  echo "=== Patch: fix_locale_paths_pre ==="
  echo "  Target: " & filePath
  if not fileExists(filePath):
    echo "  [FAIL] File not found: " & filePath
    quit(1)
  let input = readFile(filePath)
  let output = apply(input)
  if output != input:
    writeFile(filePath, output)
  echo "  [PASS] index.pre.js locale guard satisfied"
