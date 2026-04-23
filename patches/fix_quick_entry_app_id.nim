# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
#
# Give the Quick Entry BrowserWindow its own Wayland app_id (and X11
# WM_CLASS) so it can be addressed independently from the main Claude
# window - primarily so GNOME shell-extension users can blacklist the
# Quick Entry pill without also disabling effects on the main chat
# window.
#
# ============================================================================
# Problem
# ============================================================================
# The Quick Entry is a transparent, frameless second BrowserWindow
# hardcoded to 606 x 470 px so a small pill can grow vertically for
# multi-line input. At rest most of that area is transparent, so only
# the renderer-drawn pill should be visible.
#
# GNOME shell extensions that add uniform rounded corners + drop
# shadow (Rounded Window Corners Reborn, Unite, ...) decorate every
# window by attaching a child actor filled with a solid opaque
# background and a CSS `box-shadow`, clipped to a rounded rectangle
# the size of the window. On opaque windows the app's own pixels
# cover that decoration, so only the soft shadow spilling past the
# edges is visible. On the transparent Quick Entry the decoration
# shows through the transparent area: the user sees a large opaque
# rectangle with a shadow, and the real pill floating in its
# top-left corner (issue #39).
#
# The extensions let users exclude windows via a `WM_CLASS` /
# Wayland `app_id` blacklist, but Electron assigns app_id
# process-wide, so the main Claude window and Quick Entry share
# `com.anthropic.claude-desktop` and can only be blacklisted
# together. The user loses rounded corners on the main window just
# to hide the opaque rectangle behind Quick Entry, or keeps the
# rectangle.
#
# ============================================================================
# Why other "quieter" fixes don't work on Wayland
# ============================================================================
# Several obvious workarounds have been tried and rejected:
#
#  - **Setting `type: "toolbar"` (or "notification", "dock", ...) on the
#    BrowserWindow options.** On X11 this sets
#    `_NET_WM_WINDOW_TYPE_TOOLBAR`, which Mutter exposes as
#    `Meta.WindowType.TOOLBAR`, which the extension skips because it
#    only decorates NORMAL/DIALOG/MODAL_DIALOG windows. On native
#    Wayland, however, Chromium/Ozone does not translate Electron's
#    `type` option into anything visible to Mutter: the xdg_toplevel
#    is created like a normal window and Mutter maps it to
#    `Meta.WindowType.NORMAL`. Verified by running the extension in
#    debug mode and observing `win.windowType = 0` (= NORMAL) on the
#    Quick Entry.
#
#  - **Shrinking the BrowserWindow to exactly the card size** so there
#    is no empty area for the extension to paint over. Works
#    cosmetically, but breaks multi-line input (user would have to
#    scroll inside the textarea) and needs CSS/JS patches to keep the
#    card's first line aligned with the logo when the textarea grows.
#    Has a visible 8 px content shift at the 40 -> 56 px textarea
#    transition that cannot be eliminated without further CSS hacks.
#    Also does nothing to stop the extension from (uselessly)
#    re-painting on every resize.
#
#  - **Calling `xdotool set_window --class`** after creation. Works
#    only on X11/XWayland. Native Wayland has no protocol for a client
#    to change another window's app_id.
#
#  - **Spawning Quick Entry as a separate Electron process with a
#    different binary symlink name.** Was considered. Much more
#    invasive (two processes, IPC, spawn latency) and only needed if
#    the CHROME_DESKTOP trick below doesn't work - which turned out
#    not to be the case.
#
# ============================================================================
# What actually controls the Wayland app_id
# ============================================================================
# Chromium's Ozone-Wayland backend calls `xdg_toplevel.set_app_id`
# when a BrowserWindow is constructed. The value it sends comes from
# `GetXdgAppId()` in `chrome/browser/shell_integration_linux.cc`:
#
#     std::optional<std::string> GetXdgAppId() {
#       auto name = GetDesktopName();  // reads $CHROME_DESKTOP
#       if (!name) return {};
#       if (name->ends_with(".desktop"))
#         name->resize(size(*name) - 8);
#       return *name;
#     }
#
# So the app_id is the basename of whatever the `CHROME_DESKTOP`
# environment variable points at, with any `.desktop` suffix stripped.
# The launcher script sets `CHROME_DESKTOP=com.anthropic.claude-desktop.desktop`
# at startup, so every BrowserWindow gets
# `app_id = com.anthropic.claude-desktop` by default.
#
# Critically, Chromium re-reads `CHROME_DESKTOP` at each new
# `xdg_toplevel.set_app_id` call, not once at process start. If we
# change the env var BEFORE `new BrowserWindow(...)` runs, the
# resulting window gets whatever id we set. This was verified
# empirically: with the swap below in place, the extension's debug
# log reports
#     wmClass = com.anthropic.claude-quick-entry
# for the Quick Entry window, while the main window keeps
#     wmClass = com.anthropic.claude-desktop
#
# Electron's `app.setDesktopName()` is a thin wrapper around setting
# the same env var from the JS side, so we call both for safety.
#
# ============================================================================
# Fix
# ============================================================================
# Two small injections in the Quick Entry setup chain:
#
#  1. BEFORE the `new wA.BrowserWindow(...)` that creates `Po`:
#     set CHROME_DESKTOP to "com.anthropic.claude-quick-entry.desktop"
#     (and call app.setDesktopName).
#
#  2. ON the window's first "ready-to-show" event: reset CHROME_DESKTOP
#     (and app.setDesktopName) back to
#     "com.anthropic.claude-desktop.desktop", so any later
#     BrowserWindow the app creates (dialogs, printing preview, etc.)
#     gets the original app_id again.
#
# We use `.once("ready-to-show")` rather than a blind setTimeout
# because ready-to-show guarantees Chromium has dispatched
# `xdg_toplevel.set_app_id` to the compositor. Resetting any earlier
# risks a race where the protocol message goes out with the reset
# value.
#
# Quick Entry itself is only constructed once per session (upstream
# guards with `Po || (Po = new ...)`), so it retains its custom app_id
# for its whole lifetime even though the env var is restored.
#
# ============================================================================
# How users act on this
# ============================================================================
# With the patch in place, GNOME shell-extension users who see the
# opaque-rectangle symptom can simply add
#     com.anthropic.claude-quick-entry
# to the extension's blacklist (Rounded Window Corners Reborn,
# Unite, Blur My Shell, ...). The Quick Entry then renders with no
# compositor-side shadow or rounded-corner paint, so the transparent
# empty area around the card is actually transparent. The main Claude
# window is unaffected because its app_id is unchanged.
#
# Users who don't run such an extension see no difference at all.
#
# ============================================================================
# Pattern anchors
# ============================================================================
# Anchor 1: `([\w$]+)||(([\w$]+)=new ([\w$]+).BrowserWindow({titleBarStyle:"hidden"`
#           The `||` short-circuit plus the exact options prefix is
#           only present for the Quick Entry constructor in the bundle.
#           Minifier renames force us to capture the winVar and
#           electronVar; nim-regex lacks backreferences so we verify
#           the two identifier captures agree in the callback.
#
# Anchor 2: the `Po.loadFile(.../quick-window.html)` call. It's the
#           cleanest statement in the setup comma-chain to append our
#           `.once("ready-to-show")` reset to.

import std/[os]
import regex

const MAIN_APP_ID = "com.anthropic.claude-desktop"
const QE_APP_ID = "com.anthropic.claude-quick-entry"

proc apply*(input: string): string =
  result = input

  # -----------------------------------------------------------------
  # 1. Pre-create: swap CHROME_DESKTOP to the Quick Entry id.
  # -----------------------------------------------------------------
  let preCreatePattern = re2(
    r"""([\w$]+)\|\|\(([\w$]+)=new ([\w$]+)\.BrowserWindow\(\{titleBarStyle:"hidden""""
  )
  var preCount = 0
  result = result.replace(
    preCreatePattern,
    proc(m: RegexMatch2, s: string): string =
      let w1 = s[m.group(0)]
      let w2 = s[m.group(1)]
      let electronVar = s[m.group(2)]
      if w1 != w2:
        # The short-circuit target and assignment LHS must be the same
        # var; bail out by reconstructing the original match.
        return
          w1 & "||(" & w2 & "=new " & electronVar &
          ".BrowserWindow({titleBarStyle:\"hidden\""
      inc preCount
      w1 & "||(" & "process.env.CHROME_DESKTOP=\"" & QE_APP_ID & ".desktop\"," &
        "(typeof " & electronVar & ".app.setDesktopName===\"function\"&&" & electronVar &
        ".app.setDesktopName(\"" & QE_APP_ID & ".desktop\"))," & w2 & "=new " &
        electronVar & ".BrowserWindow({titleBarStyle:\"hidden\"",
  )
  if preCount != 1:
    echo "  [FAIL] Expected 1 Quick Entry pre-create pattern, got " & $preCount
    quit(1)
  echo "  [OK] CHROME_DESKTOP swap to " & QE_APP_ID & " inserted before BrowserWindow: " &
    $preCount & " match(es)"

  # -----------------------------------------------------------------
  # 2. Post-create: schedule reset on the window's ready-to-show.
  # -----------------------------------------------------------------
  let loadFilePattern = re2(
    r"""(([\w$]+)\.loadFile\(([\w$]+)\.join\(([\w$]+)\.app\.getAppPath\(\),"\.vite/renderer/quick_window/quick-window\.html"\)\))"""
  )
  var postCount = 0
  result = result.replace(
    loadFilePattern,
    proc(m: RegexMatch2, s: string): string =
      inc postCount
      let original = s[m.group(0)]
      let winVar = s[m.group(1)]
      let electronVar = s[m.group(3)]
      original & "," & winVar & ".once(\"ready-to-show\",()=>{" & "try{" &
        "process.env.CHROME_DESKTOP=\"" & MAIN_APP_ID & ".desktop\";" & "typeof " &
        electronVar & ".app.setDesktopName===\"function\"&&" & electronVar &
        ".app.setDesktopName(\"" & MAIN_APP_ID & ".desktop\");" &
        "}catch(__qeAppIdResetErr){}" & "})",
  )
  if postCount != 1:
    echo "  [FAIL] Expected 1 Quick Entry loadFile pattern, got " & $postCount
    quit(1)
  echo "  [OK] CHROME_DESKTOP reset to " & MAIN_APP_ID & " scheduled on ready-to-show: " &
    $postCount & " match(es)"

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_quick_entry_app_id <file>"
    quit(1)
  let filePath = paramStr(1)
  echo "=== Patch: fix_quick_entry_app_id ==="
  echo "  Target: " & filePath
  let input = readFile(filePath)
  let output = apply(input)
  writeFile(filePath, output)
  echo "  [PASS] Quick Entry app_id swap patched"
