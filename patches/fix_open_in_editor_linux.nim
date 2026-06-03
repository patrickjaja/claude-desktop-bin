# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
#
# Make "Open in VS Code / Cursor / Zed / Windsurf" work in Local Code Sessions
# on Linux.
#
# Root cause:
#   The editor-launcher class (Lkr) and the LocalSessions controller both gate
#   their entire flow on Electron's `app.getApplicationInfoForProtocol(url)`.
#   That API is macOS + Windows only — on Linux it never resolves a populated
#   `{path, icon}` object, so:
#     - isVSCodeInstalled()        always returns false
#     - getInstalledEditors()      reports every editor as installed:false
#     - openInVSCode() / openInEditor() bail out at the first if-check
#   The "Open in VS Code" button is therefore hidden/disabled, or click is a
#   silent no-op.
#
# Fix:
#   On Linux, replace each `<x>.app.getApplicationInfoForProtocol(P)` call
#   with a synchronous shim built on top of `app.getApplicationNameForProtocol`,
#   which IS implemented on Linux and returns the handler's display name (e.g.
#   "Visual Studio Code - URL Handler", "Zed", "Windsurf") or an empty string
#   when no handler is registered.
#
#   The shim returns `{path: name, name: name, icon: stub}` for a registered
#   handler and `null` when none — the same shape the rest of the code already
#   checks via `n != null && n.path`. The `await` on the call site is harmless
#   on a non-Promise value, so we leave it in place.
#
#   `shell.openExternal("vscode://file/...")` already works on Linux as long
#   as the editor's .desktop file claims the URL scheme, so the open path
#   itself needs no changes.
#
#   We also short-circuit the `getFileIcon` fallback inside getInstalledEditors
#   on Linux. The "path" we provide is a handler name, not a real file path,
#   so calling getFileIcon on it can throw — and the surrounding try/catch
#   would then falsely report installed:false. We don't ship icons on Linux
#   (per user request); the UI tolerates `iconDataUrl: undefined`.

import std/[os, strformat]
import regex

proc apply*(input: string): string =
  result = input

  # ── Patch 1: Linux-aware shim for getApplicationInfoForProtocol ────────
  # Every call site has the shape `<var>.app.getApplicationInfoForProtocol(<arg>)`
  # where <var> is the minified Electron import binding (e.g. `gA`) and <arg>
  # is a protocol literal or a member access on a protocol-table entry.
  # We capture both so the rewrite preserves the original binding.
  let pattern1 =
    re2"""(\w+)\.app\.getApplicationInfoForProtocol\(([^()]+)\)"""

  var count1 = 0
  result = result.replace(
    pattern1,
    proc(m: RegexMatch2, s: string): string =
      inc count1
      let v = s[m.group(0)]
      let a = s[m.group(1)]
      "(process.platform===\"linux\"?" &
        "(_n=>_n?{path:_n,name:_n,icon:{isEmpty:()=>!0}}:null)" &
        "(" & v & ".app.getApplicationNameForProtocol(" & a & "))" &
        ":" & v & ".app.getApplicationInfoForProtocol(" & a & "))",
  )
  # Expected sites (clean upstream bundle, 2026-05 builds):
  #   1× mailto link-open dialog (app-name/icon for "Open email link?")
  #   1× external link-open dialog (app-name/icon for "Open link?")
  #   1× LocalSessions.isVSCodeInstalled
  #   4× Lkr (editor launcher): isVSCodeInstalled, openInVSCode,
  #                              getInstalledEditors, openInEditor
  if count1 < 5:
    echo &"  [FAIL] getApplicationInfoForProtocol shim: {count1} match(es), expected >= 5"
    raise newException(
      ValueError,
      "fix_open_in_editor_linux: too few getApplicationInfoForProtocol sites",
    )
  echo &"  [OK] getApplicationInfoForProtocol shim: {count1} call site(s) wrapped"

  # ── Patch 2: skip getFileIcon fallback on Linux in getInstalledEditors ─
  # The handler "path" we synthesize on Linux is a friendly name, not a real
  # file path; calling `app.getFileIcon(<name>, {size:"normal"})` on it may
  # throw and trip the enclosing try/catch — which would push the editor as
  # installed:false despite a registered handler.
  # nim-regex (NFA-based) doesn't support backreferences, so we capture all
  # three uses of the icon-variable separately and verify they refer to the
  # same minified identifier at runtime.
  let pattern2 =
    re2"""\(!(\w+)\|\|(\w+)\.isEmpty\(\)\)&&\((\w+)=await (\w+)\.app\.getFileIcon\((\w+)\.path,\{size:"normal"\}\)\)"""

  var count2 = 0
  result = result.replace(
    pattern2,
    proc(m: RegexMatch2, s: string): string =
      let a1 = s[m.group(0)]
      let a2 = s[m.group(1)]
      let a3 = s[m.group(2)]
      let v = s[m.group(3)]
      let n = s[m.group(4)]
      if a1 != a2 or a1 != a3:
        return s[m.boundaries]
      inc count2
      "(!" & a1 & "||" & a1 & ".isEmpty())&&process.platform!==\"linux\"&&(" & a1 &
        "=await " & v & ".app.getFileIcon(" & n & ".path,{size:\"normal\"}))",
  )
  if count2 < 1:
    echo "  [FAIL] getFileIcon Linux guard: 0 matches"
    raise newException(
      ValueError, "fix_open_in_editor_linux: getFileIcon fallback pattern not found"
    )
  echo &"  [OK] getFileIcon Linux guard: {count2} call site(s)"

  if result == input:
    raise newException(ValueError, "fix_open_in_editor_linux: no changes made")

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_open_in_editor_linux <path_to_index.js>"
    quit(1)
  let filePath = paramStr(1)
  echo "=== Patch: fix_open_in_editor_linux ==="
  echo &"  Target: {filePath}"
  if not fileExists(filePath):
    echo &"  [FAIL] File not found: {filePath}"
    quit(1)
  let input = readFile(filePath)
  let output = apply(input)
  if output != input:
    writeFile(filePath, output)
    echo "  [PASS] Open-in-editor patched for Linux"
  else:
    echo "  [FAIL] No changes made"
    quit(1)
