# @patch-target: app.asar.contents/.vite/build/index.pre.js
# @patch-type: nim
#
# Regression guard: managed/enterprise config is read natively on Linux in the
# EARLY BOOTSTRAP bundle (index.pre.js).
#
# This is the bootstrap sibling of fix_enterprise_config_linux.nim. index.pre.js
# runs before the main process and decides whether the app enters 3p / enterprise /
# inference-gateway mode (relocating Electron userData to ~/.config/Claude-3p). If
# the bootstrap can't see the Linux managed config, the app boots in 1p mode no
# matter what index.js does later.
#
# History: we used to inject a /etc/claude-desktop/enterprise.json reader here too
# (the index.js patch could not reach this file — the orchestrator stages each
# @patch-target in isolation).
#
# The official Linux .deb UPSTREAMED a native Linux reader in the bootstrap with the
# SAME hardened shape as index.js (different minified names), reading
# `/etc/claude-desktop/managed-settings.json`:
#     const yf="/etc/claude-desktop",pa=`${yf}/managed-settings.json`;
#     function u$(){...e=Dn.openSync(pa,Dn.constants.O_RDONLY|Dn.constants.O_NOFOLLOW|...);...}
#
# Per CLAUDE.md Rule 6, this patch now POSITIVELY asserts that native bootstrap read
# path is present (path constant + O_NOFOLLOW reader). If a future bump removes it,
# 3p/enterprise mode would never activate on Linux — this FAILs loud so that
# regression is caught at build time instead of shipping silently (which is exactly
# how v1.15200.0 shipped with 3p broken).
#
# Migration note (docs, not enforceable here): upstream reads managed-settings.json,
# our old patch read enterprise.json — see fix_enterprise_config_linux.nim.

import std/[os]
import regex

proc apply*(input: string): string =
  result = input

  var m1: RegexMatch2
  let pathConst = input.find(
    re2"""const [\w$]+="/etc/claude-desktop",[\w$]+=`\$\{[\w$]+\}/managed-settings\.json`""",
    m1,
  )
  var m2: RegexMatch2
  let nativeReader = input.find(
    re2"""[\w$]+\.openSync\([\w$]+,[\w$]+\.constants\.O_RDONLY\|[\w$]+\.constants\.O_NOFOLLOW""",
    m2,
  )
  if pathConst and nativeReader:
    echo "  [OK] Native Linux managed-settings.json bootstrap reader present " &
      "(/etc/claude-desktop + O_NOFOLLOW openSync) — regression guard satisfied"
    return result

  echo "  [FAIL] Native Linux bootstrap managed-config reader MISSING " & "(pathConst=" &
    $pathConst & " reader=" & $nativeReader &
    ") — 3p/enterprise mode would never activate"
  echo "         Re-audit fix_enterprise_config_linux_pre against index.pre.js."
  quit(1)

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_enterprise_config_linux_pre <path_to_index.pre.js>"
    quit(1)
  let filePath = paramStr(1)
  echo "=== Patch: fix_enterprise_config_linux_pre (regression guard) ==="
  echo "  Target: " & filePath
  if not fileExists(filePath):
    echo "  [FAIL] File not found: " & filePath
    quit(1)
  let input = readFile(filePath)
  let output = apply(input)
  if output != input:
    writeFile(filePath, output)
  echo "  [PASS] Native Linux enterprise/managed config bootstrap reader confirmed (no patch needed)"
