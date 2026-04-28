# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
#
# Patch Claude Desktop to fix "Start at login" / "Start in system tray" on Linux.
#
# Problem (three layers):
# 1. isStartupOnLoginEnabled() must not call Electron's getLoginItemSettings() on Linux
#    because it returns undefined values for openAtLogin/executableWillLaunchAtLogin,
#    causing the Settings toggle to always show as disabled.
# 2. setStartupOnLoginEnabled() must manage the XDG autostart file directly, because
#    Electron's setLoginItemSettings() on Linux does not add --startup to the Exec line,
#    so the main window would always appear even when started at login.
# 3. GNOME session restore re-launches Claude after reboot without --startup because
#    gnome-session-service re-launches saved apps independently of XDG autostart.
#    No env var distinguishes a session-restore launch from a normal user launch.
#
# Fix:
# - isStartupOnLoginEnabled(): check ~/.config/autostart/com.anthropic.claude-desktop[-PROFILE].desktop
# - setStartupOnLoginEnabled(enabled): create/remove that file with
#   Exec=/usr/bin/claude-desktop [--profile=PROFILE] --startup
# - Augment the --startup argv check: /run/user/UID/bus is created by systemd-logind at
#   session start. If Claude starts within 60 s of that mtime, assume session-restore and
#   suppress the main window (treat as --startup launch).
#
# Profile-aware: the injected JS reads process.env.CLAUDE_PROFILE at runtime so each
# profile manages its own autostart file independently. Toggling "Start at login" inside
# the work profile creates com.anthropic.claude-desktop-work.desktop with --profile=work
# in the Exec line, so the right profile auto-starts at login.

import std/[os, strutils]
import regex

proc apply*(input: string): string =
  var patchesApplied = 0
  const expectedPatches = 3

  # Pattern 1: isStartupOnLoginEnabled function
  # Replace the env-var short-circuit with a Linux XDG check, then keep the env-var check.
  let pattern1 =
    re2"""isStartupOnLoginEnabled\(\)\{if\(process\.env\.CLAUDE_AVOID_READING_LOGING_ITEM_SETTINGS\)return!1;"""
  const replacement1 =
    """isStartupOnLoginEnabled(){if(process.platform==="linux"){try{const _ps=process.env.CLAUDE_PROFILE?"-"+process.env.CLAUDE_PROFILE:"";return require("fs").existsSync(require("path").join(require("os").homedir(),".config","autostart","com.anthropic.claude-desktop"+_ps+".desktop"))}catch(e){return false}}if(process.env.CLAUDE_AVOID_READING_LOGING_ITEM_SETTINGS)return!1;"""

  # Already-applied sentinel: Pattern 1 changes the function to start with platform check.
  # Must be specific - other patches (fix_asar_workspace_cwd, fix_browser_tools_linux)
  # also inject require("os").homedir(), so that alone is not a reliable sentinel.
  if """isStartupOnLoginEnabled(){if(process.platform==="linux")""" in input:
    echo "  [INFO] isStartupOnLoginEnabled: already patched"
    patchesApplied += 1
    result = input
  else:
    var count1 = 0
    result = input.replace(
      pattern1,
      proc(m: RegexMatch2, s: string): string =
        inc count1
        replacement1,
    )
    if count1 > 0:
      patchesApplied += count1
      echo "  [OK] isStartupOnLoginEnabled: " & $count1 & " match(es)"
    else:
      echo "  [FAIL] isStartupOnLoginEnabled: 0 matches"

  # Pattern 2: setStartupOnLoginEnabled function
  # Inject Linux XDG autostart file management (create/remove with --startup in Exec line).
  let pattern2 =
    re2"""setStartupOnLoginEnabled\(([\w$]+)\)\{([\w$]+)\.debug\("Toggling"""

  # Already-applied sentinel: Pattern 2 adds X-GNOME-Autostart-enabled (unique to our patch)
  let intermediate = result
  if "X-GNOME-Autostart-enabled" in input:
    echo "  [INFO] setStartupOnLoginEnabled: already patched"
    patchesApplied += 1
  else:
    var count2 = 0
    result = intermediate.replace(
      pattern2,
      proc(m: RegexMatch2, s: string): string =
        inc count2
        let argVar = s[m.group(0)]
        let loggerVar = s[m.group(1)]
        """setStartupOnLoginEnabled(""" & argVar &
          """){if(process.platform==="linux"){const _ps=process.env.CLAUDE_PROFILE?"-"+process.env.CLAUDE_PROFILE:"";const _pe=process.env.CLAUDE_PROFILE?" --profile="+process.env.CLAUDE_PROFILE:"";const _pn=process.env.CLAUDE_PROFILE?" ("+process.env.CLAUDE_PROFILE+")":"";const _f=require("path").join(require("os").homedir(),".config","autostart","com.anthropic.claude-desktop"+_ps+".desktop");if(""" &
          argVar &
          """){require("fs").mkdirSync(require("path").dirname(_f),{recursive:true});require("fs").writeFileSync(_f,"[Desktop Entry]\nType=Application\nName=Claude"+_pn+"\nExec=/usr/bin/claude-desktop"+_pe+" --startup\nX-GNOME-Autostart-enabled=true\n")}else{try{require("fs").unlinkSync(_f)}catch(e){}}return}""" &
          loggerVar & """.debug("Toggling""",
    )
    if count2 > 0:
      patchesApplied += count2
      echo "  [OK] setStartupOnLoginEnabled: " & $count2 & " match(es)"
    else:
      echo "  [FAIL] setStartupOnLoginEnabled: 0 matches"

  # Pattern 3: GNOME session restore detection.
  # gnome-session-service re-launches saved apps without --startup. There is no env var
  # to distinguish this from a normal user launch.
  # Strategy: check the mtime of the Wayland compositor socket (WAYLAND_DISPLAY env var,
  # e.g. /run/user/UID/wayland-1). The compositor socket is created when the graphical
  # session starts -- even when systemd lingering is enabled (which keeps /run/user/UID/bus
  # alive from boot, making the bus socket mtime unreliable as a login-time proxy).
  # X11 fallback: uses the bus socket (works for X11 users without lingering).
  # If Claude starts within 60 s of that timestamp, assume session-restore and hide window.
  # Limitation: a manual launch within 60 s of compositor start is also suppressed.
  let pattern3 = re2"""([\w$]+)\.argv\.includes\("--startup"\)"""

  let intermediate2 = result
  if "_b.mtimeMs" in intermediate2:
    echo "  [INFO] GNOME session restore: already patched"
    patchesApplied += 1
  else:
    var count3 = 0
    result = intermediate2.replace(
      pattern3,
      proc(m: RegexMatch2, s: string): string =
        inc count3
        if count3 > 1:
          return s[m.group(0)] & ".argv.includes(\"--startup\")"
        let processVar = s[m.group(0)]
        processVar &
          ".argv.includes(\"--startup\")||process.platform===\"linux\"&&(()=>{try{const _uid=String(process.getuid());const _wd=process.env.WAYLAND_DISPLAY;const _sock=_wd?require(\"path\").join(\"/run/user\",_uid,_wd):require(\"path\").join(\"/run/user\",_uid,\"bus\");const _b=require(\"fs\").statSync(_sock);return(Date.now()-_b.mtimeMs)<60000}catch(e){return false}})()",
    )
    if count3 > 0:
      patchesApplied += count3
      echo "  [OK] GNOME session restore: " & $count3 & " match(es)"
    else:
      echo "  [FAIL] GNOME session restore: 0 matches"

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
    echo "  [PASS] Startup settings patched successfully"
  else:
    echo "  [WARN] No changes made (patterns matched but already applied)"
