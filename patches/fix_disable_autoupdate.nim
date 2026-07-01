# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
#
# Regression guard: auto-updater stays disabled on the native Linux .deb.
#
# History: the Windows Claude Desktop package shipped Squirrel auto-update logic
# whose isInstalled check (a `if(process.platform!=="win32")return X.app.isPackaged`
# function) returned true for our repackaged app, firing false "Update downloaded"
# notifications. We used to inject `if(process.platform==="linux")return!1;` at the
# start of that function.
#
# The official Linux .deb refactored this. isInstalled is now:
#     function xer(){return!!bO.forceInstalled}
# and the auto-update manager bails immediately when forceInstalled is false:
#     async function P1n(){if(!bO.forceInstalled)return; ...}
# On the .deb, `bO.forceInstalled` is never assigned a truthy value, so isInstalled
# is always false and the updater never initializes — upstream now does natively
# what our patch used to force. There is nothing left to inject.
#
# Per CLAUDE.md Rule 6 (feature upstreamed -> convert to regression guard, never
# delete silently), this patch now POSITIVELY asserts the upstreamed end-state:
#   1. isInstalled is the `return!!<obj>.forceInstalled` shape, AND
#   2. nothing in the bundle assigns forceInstalled a truthy value.
# If a future upstream bump makes forceInstalled truthy (or restores a platform
# isPackaged check), this FAILs loud so the false-update-notification regression
# is caught at build time instead of shipping to users.

import std/[os, strutils]
import regex

proc apply*(input: string): string =
  result = input

  # 1. Positive assertion: the forceInstalled-based isInstalled function exists.
  let isInstalledPat = re2"""function [\w$]+\(\)\{return!![\w$]+\.forceInstalled\}"""
  var m: RegexMatch2
  if not input.find(isInstalledPat, m):
    echo "  [FAIL] Native isInstalled (return!!<obj>.forceInstalled) NOT found"
    echo "         Upstream may have changed the updater gate — re-audit fix_disable_autoupdate."
    echo "         Debug: rg -o 'function [\\w$]+\\(\\)\\{return!![\\w$]+\\.forceInstalled\\}' index.js"
    quit(1)

  # 2. Capture the config object name (e.g. `bO`) so we can assert it is never
  #    set truthy. group(0) is the first () group — none here, so re-extract via
  #    a capturing pattern.
  let capPat = re2"""function [\w$]+\(\)\{return!!([\w$]+)\.forceInstalled\}"""
  var cm: RegexMatch2
  discard input.find(capPat, cm)
  let cfgVar = input[cm.group(0)]

  # 3. Assert forceInstalled is never assigned a truthy value. Upstream uses it
  #    purely as a read-only gate on the .deb. A `<cfg>.forceInstalled=!0` /
  #    `=true` / `=1` would re-arm the updater. (nim-regex is NFA-based and has no
  #    lookahead, so we check the concrete truthy assignment forms by substring.)
  let truthyForms = [
    cfgVar & ".forceInstalled=!0",
    cfgVar & ".forceInstalled=true",
    cfgVar & ".forceInstalled=1",
    "forceInstalled:!0",
    "forceInstalled:true",
  ]
  for truthy in truthyForms:
    if truthy in input:
      echo "  [FAIL] forceInstalled assigned/initialized truthy (" & truthy &
        ") — auto-update may re-arm on Linux"
      quit(1)

  echo "  [OK] Auto-update disabled natively on .deb (isInstalled via " & cfgVar &
    ".forceInstalled, never truthy) — regression guard satisfied"

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_disable_autoupdate <path_to_index.js>"
    quit(1)
  let filePath = paramStr(1)
  echo "=== Patch: fix_disable_autoupdate (regression guard) ==="
  echo "  Target: " & filePath
  if not fileExists(filePath):
    echo "  [FAIL] File not found: " & filePath
    quit(1)
  let input = readFile(filePath)
  let output = apply(input)
  # Guard makes no changes; success is the assertion passing.
  if output != input:
    writeFile(filePath, output)
  echo "  [PASS] Auto-updater confirmed disabled on Linux (no patch needed)"
