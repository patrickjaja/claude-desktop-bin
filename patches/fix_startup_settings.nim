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
# 3. The main window is only hidden when argv.includes("--startup") is true (Linux path).
#    Without --startup in the autostart Exec line, the window always shows.
#
# Fix:
# - isStartupOnLoginEnabled(): check ~/.config/autostart/com.anthropic.claude-desktop.desktop
# - setStartupOnLoginEnabled(enabled): create/remove that file with Exec=claude-desktop --startup

import std/[os, strutils]
import regex

proc apply*(input: string): string =
  var patchesApplied = 0
  const expectedPatches = 2

  # Pattern 1: isStartupOnLoginEnabled function
  # Replace the env-var short-circuit with a Linux XDG check, then keep the env-var check.
  let pattern1 =
    re2"""isStartupOnLoginEnabled\(\)\{if\(process\.env\.CLAUDE_AVOID_READING_LOGING_ITEM_SETTINGS\)return!1;"""
  const replacement1 =
    """isStartupOnLoginEnabled(){if(process.platform==="linux"){try{return require("fs").existsSync(require("path").join(require("os").homedir(),".config","autostart","com.anthropic.claude-desktop.desktop"))}catch(e){return false}}if(process.env.CLAUDE_AVOID_READING_LOGING_ITEM_SETTINGS)return!1;"""

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
          """){if(process.platform==="linux"){const _f=require("path").join(require("os").homedir(),".config","autostart","com.anthropic.claude-desktop.desktop");if(""" &
          argVar &
          """){require("fs").mkdirSync(require("path").dirname(_f),{recursive:true});require("fs").writeFileSync(_f,"[Desktop Entry]\nType=Application\nName=Claude\nExec=claude-desktop --startup\nX-GNOME-Autostart-enabled=true\n")}else{try{require("fs").unlinkSync(_f)}catch(e){}}return}""" &
          loggerVar & """.debug("Toggling""",
    )
    if count2 > 0:
      patchesApplied += count2
      echo "  [OK] setStartupOnLoginEnabled: " & $count2 & " match(es)"
    else:
      echo "  [FAIL] setStartupOnLoginEnabled: 0 matches"

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
