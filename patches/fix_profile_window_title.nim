# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
#
# Suffix the main window title with the active profile name when CLAUDE_PROFILE
# is set. "Claude" → "Claude (work)" so users can tell windows apart in
# Alt-Tab, taskbar tooltips, and screenshots without relying on icon shape.
#
# How it works:
#   - The main window is constructed by the unsuffixed-named function
#     `function NAME(arg){return WIN=new ELECTRON.BrowserWindow(arg),...}`.
#     The original passes no `title:` option, so the initial title is
#     `app.getName()`; once React loads, Chromium emits page-title-updated
#     and Electron applies whatever document.title says.
#   - Unlike popup windows (which go through a `qkn`-style helper that calls
#     event.preventDefault() to lock the title), the main window has no such
#     handler — the renderer's title flows through verbatim.
#   - We inject a tiny comma-expression right after the BrowserWindow
#     construction that, when CLAUDE_PROFILE is set, (a) calls setTitle()
#     with "Claude (PROFILE)" for the brief pre-React window, and (b) hooks
#     page-title-updated to preventDefault and re-set with the suffix
#     appended. Conversation names like "My chat" become "My chat (work)".
#
# Default profile (CLAUDE_PROFILE unset) → no listener attached, no behavior
# change.
#
# Break risk: LOW. Targets the standard Electron BrowserWindow API with
# flexible regex on minified variable names.

import std/[os, strformat, strutils]
import std/nre

const SENTINEL = "__cdb_titleHook"

proc apply*(input: string): string =
  result = input

  if SENTINEL in result:
    echo "  [INFO] Window title hook already applied"
    echo "  [PASS] No changes needed (already patched)"
    return

  # function NAME(ARG){return WIN=new ELECTRON.BrowserWindow(ARG),
  let pattern = re"function ([\w$]+)\(([\w$]+)\)\{return ([\w$]+)=new ([\w$]+)\.BrowserWindow\(\2\),"

  var hits = 0
  result = result.replace(
    pattern,
    proc(m: RegexMatch): string =
      inc hits
      let funcName = m.captures[0]
      let argName = m.captures[1]
      let winVar = m.captures[2]
      let electronVar = m.captures[3]
      "function " & funcName & "(" & argName & "){return " & winVar & "=new " &
        electronVar & ".BrowserWindow(" & argName & ")," &
        # Profile-aware title injection. Wrapped in a single short-circuit
        # expression so the comma chain still type-checks; evaluates to
        # `false` (no-op) when CLAUDE_PROFILE is unset.
        "process.env.CLAUDE_PROFILE&&((globalThis." & SENTINEL & "=true)," &
        winVar & ".setTitle(\"Claude (\"+process.env.CLAUDE_PROFILE+\")\")," &
        winVar &
        ".on(\"page-title-updated\",(__cdb_ev,__cdb_t)=>{__cdb_ev.preventDefault();" &
        winVar & ".setTitle(__cdb_t+\" (\"+process.env.CLAUDE_PROFILE+\")\")}))," ,
  )

  if hits == 1:
    echo &"  [OK] Main window title hook injected (function={hits} match)"
  elif hits > 1:
    # Defensive: should be exactly one main-window-construction site. If the
    # pattern starts matching multiple BrowserWindow factories, that's a
    # signal upstream changed shape and we should investigate rather than
    # silently inject into windows that already lock their title.
    echo &"  [FAIL] Expected 1 BrowserWindow construction site, got {hits}"
    raise newException(ValueError, "fix_profile_window_title: ambiguous match")
  else:
    echo "  [FAIL] Main window construction pattern not found"
    raise newException(ValueError, "fix_profile_window_title: 0 matches")

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_profile_window_title <file>"
    quit(1)

  let filePath = paramStr(1)
  echo "=== Patch: fix_profile_window_title ==="
  echo "  Target: " & filePath

  if not fileExists(filePath):
    echo "  [FAIL] File not found: " & filePath
    quit(1)

  let input = readFile(filePath)
  let output = apply(input)

  if output != input:
    writeFile(filePath, output)
    echo "  [PASS] Profile window title hook installed"
  # If unchanged, apply() already printed [PASS] for the already-applied case.
