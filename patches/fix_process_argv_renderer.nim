# @patch-target: app.asar.contents/.vite/build/mainView.js
# @patch-type: nim
#
# Fix process.argv being undefined in the web renderer.
#
# The preload exposes a filtered process object to the main world with only
# arch, platform, type, and versions. The Claude Code SDK web bundle
# calls process.argv.includes("--debug") during streamInput(), which throws:
#
#   TypeError: Cannot read properties of undefined (reading 'includes')
#
# This prevents Dispatch responses from rendering in the UI.
#
# Fix: Add argv as an empty array to the exposed process object, right before
# exposeInMainWorld. The empty array makes .includes() return false (correct
# behavior -- the renderer is not in debug mode).

import std/[os, strutils]
import regex

proc apply*(input: string): string =
  # Check if already patched (use flexible pattern for any variable name)
  let alreadyPatched = re2"""[\w$]+\.argv=\[\]"""
  if input.contains(alreadyPatched):
    echo "  [OK] process.argv: already patched (skipped)"
    return input

  # Primary: insert <var>.argv=[] just before exposeInMainWorld("process",<var>)
  let exposePattern =
    re2"""([\w$]+\.contextBridge\.exposeInMainWorld\("process",)([\w$]+)(\))"""
  var m: RegexMatch2
  if input.find(exposePattern, m):
    let varName = input[m.group(1)]
    let insert = varName & ".argv=[];"
    let pos = m.boundaries.a
    result = input[0 ..< pos] & insert & input[pos .. ^1]
    echo "  [OK] process.argv: added " & varName & ".argv=[] (before exposeInMainWorld)"
    return result

  # Fallback 1: after platform spoof
  let spoofPattern = re2"""([\w$]+)(\.platform="win32"\})"""
  if input.find(spoofPattern, m):
    let varName = input[m.group(0)]
    let insert = varName & ".argv=[];"
    let pos = m.boundaries.b + 1 # exclusive end of full match
    result = input[0 ..< pos] & insert & input[pos .. ^1]
    echo "  [OK] process.argv: added " & varName & ".argv=[] (after platform spoof)"
    return result

  # Fallback 2: after <var>.version=...appVersion;
  let versionPattern = re2"""([\w$]+)(\.version=[\w$]+\(\)\.appVersion;)"""
  if input.find(versionPattern, m):
    let varName = input[m.group(0)]
    let insert = varName & ".argv=[];"
    let pos = m.boundaries.b + 1 # exclusive end of full match
    result = input[0 ..< pos] & insert & input[pos .. ^1]
    echo "  [OK] process.argv: added " & varName & ".argv=[] (after version)"
    return result

  echo "  [FAIL] process.argv: could not find insertion point"
  quit(1)

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_process_argv_renderer <path_to_mainView.js>"
    quit(1)
  let filePath = paramStr(1)
  echo "=== Patch: fix_process_argv_renderer ==="
  echo "  Target: " & filePath
  if not fileExists(filePath):
    echo "  [FAIL] File not found: " & filePath
    quit(1)
  let input = readFile(filePath)
  let output = apply(input)
  if output != input:
    writeFile(filePath, output)
