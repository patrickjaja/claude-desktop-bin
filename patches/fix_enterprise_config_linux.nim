# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
#
# Regression guard: managed/enterprise config is read natively on Linux (main process).
#
# History: upstream's enterprise-config reader was darwin (CFPreferences/plist) +
# win32 (registry) only; Linux returned {}. We injected a reader for
# /etc/claude-desktop/enterprise.json, routed through the key-registration fn so
# the managed/3p gate Set was populated.
#
# The official Linux .deb UPSTREAMED a native Linux reader, with a DIFFERENT path:
#     const RVA="/etc/claude-desktop",tM=`${RVA}/managed-settings.json`;
#     function dHe(A){return A.uid===0&&(A.mode&18)===0}        // root-owned, not g/o-writable
#     function Wii(){...e=Fo.openSync(tM,Fo.constants.O_RDONLY|Fo.constants.O_NOFOLLOW|...);...}
# and the platform dispatcher routes Linux to that reader (the else branch):
#     process.platform==="darwin"?n(c):process.platform==="win32"?o(c):s(c)
# i.e. darwin->plist, win32->registry, ELSE (linux)->etc_file reader (`s`). The
# selected-source constant is `etc_file`. This is a hardened native reader
# (O_NOFOLLOW + root-ownership check), strictly better than our injected one.
#
# IMPORTANT migration note (surface in docs, NOT enforceable here): upstream reads
# `/etc/claude-desktop/managed-settings.json`, whereas our old patch read
# `/etc/claude-desktop/enterprise.json`. Deployments relying on the old filename
# must rename the file. The on-disk SCHEMA (managedMcpServers, inferenceProvider, …)
# is unchanged.
#
# Per CLAUDE.md Rule 6 (feature upstreamed -> regression guard, never silent delete),
# this patch now POSITIVELY asserts the native Linux read path is present:
#   1. the /etc/claude-desktop + managed-settings.json path constant, AND
#   2. the hardened native reader that opens it with O_NOFOLLOW.
# If a future bump removes either, this FAILs loud so the "Linux silently loses
# enterprise/3p config" regression is caught at build time.

import std/[os]
import regex

proc apply*(input: string): string =
  result = input

  # 1. Path constant: /etc/claude-desktop + managed-settings.json template.
  var m1: RegexMatch2
  let pathConst = input.find(
    re2"""const [\w$]+="/etc/claude-desktop",[\w$]+=`\$\{[\w$]+\}/managed-settings\.json`""",
    m1,
  )
  # 2. Hardened native reader actually OPENS that path (O_NOFOLLOW proves a real
  #    read, not a mere telemetry label).
  var m2: RegexMatch2
  let nativeReader = input.find(
    re2"""[\w$]+\.openSync\([\w$]+,[\w$]+\.constants\.O_RDONLY\|[\w$]+\.constants\.O_NOFOLLOW""",
    m2,
  )
  if pathConst and nativeReader:
    echo "  [OK] Native Linux managed-settings.json reader present " &
      "(/etc/claude-desktop + O_NOFOLLOW openSync) — regression guard satisfied"
    return result

  echo "  [FAIL] Native Linux managed-config reader MISSING " & "(pathConst=" &
    $pathConst & " reader=" & $nativeReader & ") — upstream may have regressed"
  echo "         Linux would silently lose enterprise/3p config. Re-audit fix_enterprise_config_linux."
  echo "         Debug: rg -o 'const [\\w$]+=\"/etc/claude-desktop\",[\\w$]+=`...managed-settings.json`' index.js"
  quit(1)

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_enterprise_config_linux <path_to_index.js>"
    quit(1)
  let filePath = paramStr(1)
  echo "=== Patch: fix_enterprise_config_linux (regression guard) ==="
  echo "  Target: " & filePath
  if not fileExists(filePath):
    echo "  [FAIL] File not found: " & filePath
    quit(1)
  let input = readFile(filePath)
  let output = apply(input)
  if output != input:
    writeFile(filePath, output)
  echo "  [PASS] Native Linux enterprise/managed config confirmed (no patch needed)"
