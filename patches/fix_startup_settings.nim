# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
#
# "Start at login" / "Start in system tray" on Linux.
#
# History (three layers, all targeting the Windows MSIX):
#   1. isStartupOnLoginEnabled() called Electron getLoginItemSettings() (returns
#      undefined on Linux) -> Settings toggle always showed disabled.
#   2. setStartupOnLoginEnabled() used Electron setLoginItemSettings() which on
#      Linux does NOT add --startup to the Exec line -> main window always shown.
#   3. GNOME session restore re-launches saved apps WITHOUT --startup -> the main
#      window pops up after every reboot.
# We used to patch all three (anchor: the env-var short-circuit
# CLAUDE_AVOID_READING_LOGING_ITEM_SETTINGS, and the "Toggling" debug log).
#
# The official Linux .deb UPSTREAMED layers 1 and 2 natively:
#   - read:  function ico(){...exists(zmA())...readFile(zmA())...!rco(...)}  reads
#            the XDG autostart .desktop and parses Hidden / X-GNOME-Autostart-enabled.
#   - write: function nco(A){...} writes/removes it, building the file with
#            function tco(){return["[Desktop Entry]","Type=Application",
#              `Name=${app.getName()}`,`Exec=${eco(process.execPath)} --startup`,
#              "X-GNOME-Autostart-enabled=true",""].join(...)}
#   - dir:   J6A() = (XDG_CONFIG_HOME||~/.config)/autostart
#   - file:  zmA() = `${basename(process.execPath)}.desktop`  (profile-aware: our
#            per-profile Electron binary has a distinct basename, so each profile
#            manages its own autostart entry — same outcome our old patch hand-rolled)
#   - setStartupOnLoginEnabled(A){...nco(A).catch(...)"Failed to update XDG autostart entry"}
# The Exec line already carries --startup, so an autostart launch hides the window.
#
# Layer 3 was NOT upstreamed: the window-show gate is purely
#   wco=!<proc>.argv.includes("--startup")
# and the whole bundle has ZERO /run/user and ZERO gnome-session references. A
# GNOME session-restore relaunch (no --startup) therefore still shows the window.
#
# So per CLAUDE.md Rule 6:
#   - P1 (read) + P2 (write): convert to REGRESSION GUARDS that positively assert
#     the native XDG autostart read/write end-state is present (FAIL loud if a
#     future bump removes it — that would silently break the Settings toggle and
#     re-introduce the always-visible-window bug).
#   - P3 (session-restore detection): KEEP as an ACTIVE patch — augment the single
#     argv.includes("--startup") gate with a compositor-socket mtime heuristic.

import std/[os, strutils]
import regex

proc apply*(input: string): string =
  var patchesApplied = 0
  const expectedPatches = 3

  # ── P1 (guard): native XDG autostart READ ────────────────────────────────
  # isStartupOnLoginEnabled now delegates to a read helper, and the autostart dir
  # resolver + filename builder are the positive proof that Linux reads the real
  # XDG autostart .desktop (not Electron's broken getLoginItemSettings()).
  var m1: RegexMatch2
  let readDelegates =
    input.find(re2"""isStartupOnLoginEnabled\(\)\{return [\w$]+\(\)\}""", m1)
  let autostartDir = input.find(
    re2"""XDG_CONFIG_HOME\|\|[\w$]+\.join\([\w$]+\.homedir\(\),"\.config"\);return [\w$]+\.join\([\w$]+,"autostart"\)""",
    m1,
  )
  let autostartFile = input.find(
    re2"""return`\$\{[\w$]+\.basename\(process\.execPath\)\}\.desktop`""", m1
  )
  if readDelegates and autostartDir and autostartFile:
    echo "  [OK] isStartupOnLoginEnabled reads XDG autostart natively " &
      "((XDG_CONFIG_HOME||~/.config)/autostart, basename(execPath).desktop) — guard satisfied"
    patchesApplied += 1
  else:
    echo "  [FAIL] Native XDG autostart READ path missing (delegate=" & $readDelegates &
      " dir=" & $autostartDir & " file=" & $autostartFile & ")"
    echo "         Upstream may have regressed startup-on-login; re-audit fix_startup_settings P1."

  # ── P2 (guard): native XDG autostart WRITE (with --startup) ───────────────
  # The .desktop builder must still emit BOTH the `--startup` flag (so autostart
  # launches hide the window) and X-GNOME-Autostart-enabled. The write helper's
  # error log is the second positive anchor.
  var m2: RegexMatch2
  let desktopBuilder = input.find(
    re2"""\[Desktop Entry\]","Type=Application",`Name=\$\{[\w$]+\.app\.getName\(\)\}`,`Exec=\$\{[\w$]+\(process\.execPath\)\} --startup`,"X-GNOME-Autostart-enabled=true"""",
    m2,
  )
  let writeErrLog = "Failed to update XDG autostart entry" in input
  if desktopBuilder and writeErrLog:
    echo "  [OK] setStartupOnLoginEnabled writes XDG autostart natively " &
      "(Exec=… --startup, X-GNOME-Autostart-enabled=true) — guard satisfied"
    patchesApplied += 1
  else:
    echo "  [FAIL] Native XDG autostart WRITE path missing (builder=" & $desktopBuilder &
      " errlog=" & $writeErrLog & ")"
    echo "         If the --startup flag or X-GNOME-Autostart-enabled disappeared, the"
    echo "         autostart window-hide / toggle would break; re-audit fix_startup_settings P2."

  # ── P3 (active patch): GNOME session-restore detection ────────────────────
  # Native gate is only `wco=!<proc>.argv.includes("--startup")`. gnome-session-service
  # re-launches saved apps WITHOUT --startup and there is no env var to distinguish it.
  # Heuristic: the Wayland compositor socket (WAYLAND_DISPLAY, e.g.
  # /run/user/UID/wayland-1) is created when the graphical session starts; X11 falls
  # back to the session bus socket. If Claude starts within 60s of that mtime, assume
  # session-restore and treat it as a --startup launch (hide the window).
  # Idempotency: positively assert OUR injected marker (`_b.mtimeMs`) is present.
  if "_b.mtimeMs" in input:
    echo "  [INFO] GNOME session-restore detection: already patched (_b.mtimeMs present)"
    patchesApplied += 1
  else:
    let pattern3 = re2"""([\w$]+)\.argv\.includes\("--startup"\)"""
    var count3 = 0
    result = input.replace(
      pattern3,
      proc(m: RegexMatch2, s: string): string =
        inc count3
        let processVar = s[m.group(0)]
        processVar &
          ".argv.includes(\"--startup\")||process.platform===\"linux\"&&(()=>{try{const _uid=String(process.getuid());const _wd=process.env.WAYLAND_DISPLAY;const _sock=_wd?require(\"path\").join(\"/run/user\",_uid,_wd):require(\"path\").join(\"/run/user\",_uid,\"bus\");const _b=require(\"fs\").statSync(_sock);return(Date.now()-_b.mtimeMs)<60000}catch(e){return false}})()",
    )
    if count3 == 1:
      echo "  [OK] GNOME session-restore detection: augmented argv --startup gate (1 match)"
      patchesApplied += 1
    elif count3 == 0:
      echo "  [FAIL] GNOME session-restore: argv.includes(\"--startup\") gate not found"
    else:
      echo "  [FAIL] GNOME session-restore: expected 1 argv --startup site, found " &
        $count3 & " — re-audit (the window-show gate may have changed shape)"
  if result.len == 0:
    result = input

  if patchesApplied < expectedPatches:
    echo "  [FAIL] Only " & $patchesApplied & "/" & $expectedPatches & " patches applied"
    quit(1)

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_startup_settings <path_to_index.js>"
    quit(1)
  let filePath = paramStr(1)
  echo "=== Patch: fix_startup_settings ==="
  echo "  Target: " & filePath
  if not fileExists(filePath):
    echo "  [FAIL] File not found: " & filePath
    quit(1)
  let input = readFile(filePath)
  let output = apply(input)
  if output != input:
    writeFile(filePath, output)
    echo "  [PASS] Startup settings: native XDG autostart confirmed + session-restore detection injected"
  else:
    echo "  [PASS] Startup settings: native XDG autostart confirmed (session-restore already patched)"
