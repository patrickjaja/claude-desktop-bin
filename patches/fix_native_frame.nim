# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
#
# Make Claude Desktop use the integrated (Windows-style) titlebar on Linux
# by default: min/max/close are drawn as an overlay inside the web content
# and the tab strip / menu / nav buttons share that bar. Upstream's Linux
# build instead opens a native GTK window because `titleBarOverlay:Io` is
# gated on `Io = process.platform === "win32"`, and the helper that pushes
# theme updates is gated the same way.
#
# Three patches together do the job:
#   1. Open the main BrowserWindow with frame:false + a real titleBarOverlay
#      style object on Linux (plus autoHideMenuBar + icon).
#   2. Open the setTitleBarOverlay theme-update gate for Linux so the
#      overlay colors follow Anthropic's `Hb` flag and the OS theme.
#   3. Replace one transparent placeholder (`cve = "#00000000"`) with
#      Anthropic's opaque window background in Linux integrated mode.
#      Electron on Wayland silently substitutes a grey strip for that
#      transparent value, so without this swap the overlay always looks
#      like a hard-coded grey block.
#
# All three behaviors gate on CLAUDE_NATIVE_TITLEBAR: unset (or anything
# other than "1") = integrated mode; "1" = restore the GTK frame. The
# launcher's `--native-titlebar` flag sets the env var.
#
# Anthropic's bundle is minified and renames identifiers between releases.
# We capture two of them (the background helper and the Electron module
# alias) at patch time so the generated code references the current names
# and we fail loudly if either disappears.
#
# Quick Entry's BrowserWindow is matched by `transparent:!0,frame:!1` and
# has no titleBarOverlay -- none of the patterns below touch it.

import std/[os, strformat, strutils]
import regex

const ICON = "/usr/share/icons/hicolor/256x256/apps/claude-desktop.png"
const LINUX_NATIVE =
  "process.platform===\"linux\"&&process.env.CLAUDE_NATIVE_TITLEBAR===\"1\""
const LINUX_INTEGRATED =
  "process.platform===\"linux\"&&process.env.CLAUDE_NATIVE_TITLEBAR!==\"1\""

proc capture(s: string, pat: Regex2, name: string): string =
  ## Capture group 1 of `pat` from `s`, or raise with `name` in the message.
  var m: RegexMatch2
  if not s.find(pat, m):
    raise newException(ValueError, "fix_native_frame: " & name & " not found")
  s[m.group(0)]

proc apply*(input: string): string =
  if "CLAUDE_NATIVE_TITLEBAR" in input:
    echo "  [INFO] already patched"
    return input
  result = input

  # Anthropic identifiers (minified, renamed between releases):
  #   bgFn      e.g. "G$" -- window background color, called as G$().
  #   electron  e.g. "cA" -- alias for require("electron"), used for
  #                          nativeTheme.shouldUseDarkColors.
  let bgFn = result.capture(
    re2"""backgroundColor:([\w$]+)\(\),opacity:""", "backgroundColor function"
  )
  let electron = result.capture(
    re2"""([\w$]+)\.nativeTheme\.shouldUseDarkColors""", "electron alias"
  )

  # Patch 1: main BrowserWindow options. We splice five runtime-conditional
  # options into the existing comma-list right after titleBarOverlay:
  #   titleBarStyle:    "default" on Linux opt-out, "hidden" otherwise.
  #   titleBarOverlay:  Anthropic-themed style object on Linux integrated,
  #                     upstream var (true on win32, false elsewhere) otherwise.
  #   frame:            false on Linux integrated, true otherwise.
  #   autoHideMenuBar:  true on Linux (Alt brings the GTK menu bar back).
  #   icon:             Linux PNG path on Linux, undefined elsewhere.
  let overlayStyle = "{color:" & bgFn & "(),symbolColor:" & electron &
    ".nativeTheme.shouldUseDarkColors?\"#fff\":\"#000\",height:36}"
  var n = 0
  result = result.replace(
    re2"""titleBarStyle:"hidden",titleBarOverlay:([\w$]+)""",
    proc(m: RegexMatch2, s: string): string =
      inc n
      "titleBarStyle:" & LINUX_NATIVE & "?\"default\":\"hidden\"," &
        "titleBarOverlay:(" & LINUX_INTEGRATED & ")?" & overlayStyle & ":" &
        s[m.group(0)] & ",frame:!(" & LINUX_INTEGRATED & ")," &
        "autoHideMenuBar:process.platform===\"linux\"," &
        "icon:process.platform===\"linux\"?\"" & ICON & "\":void 0",
  )
  if n != 1:
    raise newException(ValueError, &"main window pattern: {n}/1")
  echo &"  [OK] main window options: {n}"

  # Patch 2: setTitleBarOverlay theme-update gate. Upstream guards the
  # forEach-all-windows call with `Io&&` (win32 only). We OR in Linux
  # integrated mode so the overlay receives theme updates there too.
  n = 0
  result = result.replace(
    re2"""\bIo&&([\w$]+)\.BrowserWindow\.getAllWindows\(\)\.forEach""",
    proc(m: RegexMatch2, s: string): string =
      inc n
      "(Io||(" & LINUX_INTEGRATED & "))&&" & s[m.group(0)] &
        ".BrowserWindow.getAllWindows().forEach",
  )
  if n != 1:
    raise newException(ValueError, &"setTitleBarOverlay gate: {n}/1")
  echo &"  [OK] setTitleBarOverlay gate: {n}"

  # Patch 3: opaque-color swap inside the helper that builds the overlay
  # style. The non-Hb branch uses `cve = "#00000000"`, which Electron on
  # Linux Wayland treats as "use default" and paints as a grey strip.
  # Swap it for `bgFn()` in Linux integrated mode so the overlay actually
  # matches the window background. Two occurrences: one per theme.
  let linuxBg = "(" & LINUX_INTEGRATED & ")?" & bgFn & "():cve"
  n = 0
  result = result.replace(
    re2"""(\{color:[\w$]+\?"#[0-9a-fA-F]+":)cve(,symbolColor:)""",
    proc(m: RegexMatch2, s: string): string =
      inc n
      s[m.group(0)] & linuxBg & s[m.group(1)],
  )
  if n != 2:
    raise newException(ValueError, &"T8 cve references: {n}/2")
  echo &"  [OK] T8 cve -> bgFn() in Linux integrated mode: {n}"

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_native_frame <file>"
    quit(1)
  let file = paramStr(1)
  echo "=== Patch: fix_native_frame ==="
  echo "  Target: " & file
  let orig = readFile(file)
  let patched = apply(orig)
  if patched != orig:
    writeFile(file, patched)
    echo "  [PASS] native frame patched"
  else:
    echo "  [PASS] no changes needed"
