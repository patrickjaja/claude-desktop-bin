# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
# Fix paths that use process.resourcesPath + "app.asar" on Linux.
# Four fixes for sidecar runtime files loaded from inside app.asar:
#   1. nodeHostPath              (.vite/build/mcp-runtime/nodeHost.js)
#   2. shellPathWorker           (.vite/build/shell-path-worker/shellPathWorker.js)
#   3. directMcpHost loader      (.vite/build/mcp-runtime/directMcpHost.js)  -- issue #140
#   4. generic worker loader     (used for .vite/build/transcript-search-worker/...)
#
# Why: fix_locale_paths.nim blanket-rewrites every `process.resourcesPath` to
# `dirname(getAppPath())+"/locales"`. That is correct for locale lookups, but these
# sidecar paths are built as `join(process.resourcesPath,"app.asar",...)`, which after
# the locale rewrite becomes `resources/locales/app.asar/...` -- a path that does not
# exist (ERR_MODULE_NOT_FOUND). On Linux the package is always "packaged" and
# app.getAppPath() already resolves to the real app.asar, so we collapse each
# isPackaged ternary to its getAppPath() branch. This patch MUST run before
# fix_locale_paths.nim (the `0` prefix in the filename guarantees lexical ordering).
#
# Uses std/nre for backreference support in patterns.

import std/[os, strformat, options]
import std/nre
from std/strutils import nil

proc apply*(input: string): string =
  result = input

  const EXPECTED_PATCHES = 4
    # nodeHostPath, shellPathWorker, directMcpHost, generic worker
  var patchesApplied = 0

  # Patch 1: nodeHostPath -- replace entire ternary with app.getAppPath()
  # Pattern uses \2 backreference for path var reuse
  let pattern1 =
    re"""this\.nodeHostPath=([\w$]+)\.app\.isPackaged\?([\w$]+)\.join\(process\.resourcesPath,"app\.asar","\.vite","build","mcp-runtime","nodeHost\.js"\):\2\.join\(\1\.app\.getAppPath\(\),"\.vite","build","mcp-runtime","nodeHost\.js"\)"""

  let m1 = result.find(pattern1)
  if m1.isSome:
    let m = m1.get
    let electronVar = m.captures[0]
    let pathVar = m.captures[1]
    let replacement =
      "this.nodeHostPath=" & pathVar & ".join(" & electronVar &
      ".app.getAppPath(),\".vite\",\"build\",\"mcp-runtime\",\"nodeHost.js\")"
    result =
      result[0 ..< m.matchBounds.a] & replacement & result[m.matchBounds.b + 1 .. ^1]
    echo "  [OK] nodeHostPath: 1 match(es)"
    inc patchesApplied
  else:
    # Idempotency: after patching, the resourcesPath/app.asar branch is gone and
    # nodeHostPath is assigned the getAppPath()-relative path directly.
    if strutils.find(result, "this.nodeHostPath=") >= 0 and
        strutils.find(
          result,
          ".join(process.resourcesPath,\"app.asar\",\".vite\",\"build\",\"mcp-runtime\",\"nodeHost.js\")",
        ) < 0:
      echo "  [OK] nodeHostPath: already patched"
      inc patchesApplied
    else:
      echo "  [FAIL] nodeHostPath: 0 matches, expected 1"
      echo "  This patch must run BEFORE fix_locale_paths.py (on original code)"
      raise newException(ValueError, "fix_0_node_host: nodeHostPath pattern not found")

  # Patch 2: shellPathWorker -- replace process.resourcesPath,"app.asar" with app.getAppPath()
  let pattern2 =
    re"""(function [\w$]+\(\)\{return )([\w$]+)(\.join\()process\.resourcesPath,"app\.asar",("\.vite","build","shell-path-worker","shellPathWorker\.js"\))"""

  let m2 = result.find(pattern2)
  if m2.isSome:
    let m = m2.get
    let replacement =
      m.captures[0] & m.captures[1] & m.captures[2] &
      "require(\"electron\").app.getAppPath()," & m.captures[3]
    result =
      result[0 ..< m.matchBounds.a] & replacement & result[m.matchBounds.b + 1 .. ^1]
    echo "  [OK] shellPathWorker: 1 match(es)"
    inc patchesApplied
  else:
    # Idempotency check
    if strutils.find(
      result,
      "require(\"electron\").app.getAppPath(),\".vite\",\"build\",\"shell-path-worker\"",
    ) >= 0:
      echo "  [OK] shellPathWorker: already patched"
      inc patchesApplied
    else:
      echo "  [FAIL] shellPathWorker: 0 matches and no already-patched marker"
      raise
        newException(ValueError, "fix_0_node_host: shellPathWorker pattern not found")

  # Patch 3: directMcpHost loader (issue #140) -- collapse the isPackaged ternary.
  # ohi(): return <el>.app.isPackaged?<p>.join(process.resourcesPath,"app.asar",...A):<p>.join(<el>.app.getAppPath(),...A)
  # Becomes: return <p>.join(<el>.app.getAppPath(),...A)
  let pattern3 =
    re"""return ([\w$]+)\.app\.isPackaged\?([\w$]+)\.join\(process\.resourcesPath,"app\.asar",\.\.\.([\w$]+)\):\2\.join\(\1\.app\.getAppPath\(\),\.\.\.\3\)"""

  let m3 = result.find(pattern3)
  if m3.isSome:
    let m = m3.get
    let electronVar = m.captures[0]
    let pathVar = m.captures[1]
    let argsVar = m.captures[2]
    let replacement =
      "return " & pathVar & ".join(" & electronVar & ".app.getAppPath(),..." & argsVar &
      ")"
    result =
      result[0 ..< m.matchBounds.a] & replacement & result[m.matchBounds.b + 1 .. ^1]
    echo "  [OK] directMcpHost loader: 1 match(es)"
    inc patchesApplied
  else:
    # Idempotency: after patching, the ternary is gone but the getAppPath()/...A form
    # is identical to the original else-branch. Detect that the resourcesPath/app.asar
    # join for mcp-runtime is no longer present alongside a directMcpHost reference.
    if strutils.find(result, "\"mcp-runtime\",\"directMcpHost.js\"") >= 0 and
        strutils.find(result, ".join(process.resourcesPath,\"app.asar\",...") < 0:
      echo "  [OK] directMcpHost loader: already patched"
      inc patchesApplied
    else:
      echo "  [FAIL] directMcpHost loader: 0 matches and no already-patched marker"
      raise newException(
        ValueError, "fix_0_node_host: directMcpHost loader pattern not found"
      )

  # Patch 4: generic worker loader l7i(A,e) -- collapse the isPackaged ternary.
  # function <f>(A,e){const t=<el>.app.isPackaged?<p>.join(process.resourcesPath,"app.asar"):<el>.app.getAppPath();...}
  # Becomes: const t=<el>.app.getAppPath()
  let pattern4 =
    re"""(function [\w$]+\([\w$]+,[\w$]+\)\{const [\w$]+=)([\w$]+)\.app\.isPackaged\?([\w$]+)\.join\(process\.resourcesPath,"app\.asar"\):\2\.app\.getAppPath\(\)"""

  let m4 = result.find(pattern4)
  if m4.isSome:
    let m = m4.get
    let prefix = m.captures[0]
    let electronVar = m.captures[1]
    let replacement = prefix & electronVar & ".app.getAppPath()"
    result =
      result[0 ..< m.matchBounds.a] & replacement & result[m.matchBounds.b + 1 .. ^1]
    echo "  [OK] generic worker loader: 1 match(es)"
    inc patchesApplied
  else:
    # Idempotency: the ternary collapsed to `const t=<el>.app.getAppPath();return
    # <p>.join(t,".vite","build",A,e)`. Detect the absence of any bare
    # `?<p>.join(process.resourcesPath,"app.asar"):` ternary form (no trailing ",").
    if strutils.find(result, "\".vite\",\"build\",A,e)") >= 0 and
        strutils.find(result, ".join(process.resourcesPath,\"app.asar\"):") < 0:
      echo "  [OK] generic worker loader: already patched"
      inc patchesApplied
    else:
      echo "  [FAIL] generic worker loader: 0 matches and no already-patched marker"
      raise newException(
        ValueError, "fix_0_node_host: generic worker loader pattern not found"
      )

  # Belt-and-suspenders: every sub-patch above raises on a genuine mismatch, so
  # reaching here with fewer than EXPECTED_PATCHES means a future refactor dropped
  # a raise. Fail loudly rather than ship a half-patched bundle.
  if patchesApplied < EXPECTED_PATCHES:
    echo &"  [FAIL] Only {patchesApplied}/{EXPECTED_PATCHES} sub-patches applied"
    raise newException(ValueError, "fix_0_node_host: incomplete patch")

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_0_node_host <file>"
    quit(1)
  let file = paramStr(1)
  echo "=== Patch: fix_0_node_host ==="
  echo &"  Target: {file}"
  if not fileExists(file):
    echo &"  [FAIL] File not found: {file}"
    quit(1)
  let input = readFile(file)
  let output = apply(input)
  if output != input:
    writeFile(file, output)
    echo "  [PASS] Node host path patched successfully"
  else:
    # apply() raises unless all sub-patches succeeded or were already applied,
    # so an unchanged file here is the expected idempotent re-run, not a failure.
    echo "  [OK] No changes made (all sub-patches already applied)"
