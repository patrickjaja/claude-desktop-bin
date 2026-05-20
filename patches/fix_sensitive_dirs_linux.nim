# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
#
# Add Linux-specific sensitive directories to the protected path list.
#
# The upstream JS defines a sensitive-directories array (used to block
# sandbox mounts that overlap credential stores). It includes cross-platform
# entries (.ssh, .aws, .gnupg, ...) and platform-specific entries for macOS
# (Library/Keychains, ...) and Windows (AppData/Roaming/...), but has NO
# Linux-specific entries.
#
# This patch appends a Linux block that protects:
#   - .local/share/keyrings  (GNOME Keyring / KDE Wallet credential files)
#   - .pki                   (NSS/Chrome certificate database)
#   - .config/autostart       (XDG autostart .desktop entries)

import std/[os, strformat, strutils]
import regex

const EXPECTED_PATCHES = 1

const LINUX_DIRS_SPREAD =
  """,...process.platform==="linux"?[".local/share/keyrings",".pki",".config/autostart"]:[]"""

proc apply*(input: string): string =
  result = input
  var patchesApplied = 0

  # Already-patched detection: if our Linux block is already present, skip
  if """.platform==="linux"?[".local/share/keyrings"""" in result:
    echo "  [INFO] Linux sensitive dirs already injected"
    patchesApplied += 1
  else:
    # Strategy: find the closing of the sensitive-dirs array.
    #
    # The array structure is:
    #   const <var>=[...cross-platform...,
    #     ...process.platform==="darwin"?[...]:[] ,
    #     ...process.platform==="win32"?[...]:[]
    #   ],<nextVar>=[".zshrc",...
    #
    # In the minified JS this looks like:
    #   ..."gnupg")]:[]],sar=[".zshrc",...
    #
    # We want to inject BEFORE the outer ] that closes the sensitive-dirs array:
    #   ..."gnupg")]:[],...linux?[...]:[]],sar=[".zshrc",...
    #
    # Regex breakdown:
    #   (:\[\])  - group 0: the win32 empty-fallback ":[]"
    #   (\],)    - group 1: outer array close "]" + comma ","
    #   ([\w$]+=\["\.zshrc") - group 2: next var assignment with ".zshrc" anchor
    let pattern = re2"""(:\[\])(\],)([\w$]+=\["\.zshrc")"""

    var count = 0
    result = result.replace(
      pattern,
      proc(m: RegexMatch2, s: string): string =
        inc count
        # Reconstruct: win32 fallback + Linux spread + outer close + next var
        s[m.group(0)] & LINUX_DIRS_SPREAD & s[m.group(1)] & s[m.group(2)],
    )
    if count > 0:
      echo &"  [OK] Linux sensitive dirs injected: {count} match(es)"
      patchesApplied += 1
    else:
      echo "  [FAIL] Could not find sensitive-dirs array closing pattern"
      echo "  [HINT] Search for '.ssh' near '.aws' and '.gnupg' in the target file"

  if patchesApplied < EXPECTED_PATCHES:
    echo &"  [FAIL] Only {patchesApplied}/{EXPECTED_PATCHES} patches applied"
    quit(1)

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_sensitive_dirs_linux <file>"
    quit(1)
  let filePath = paramStr(1)
  echo "=== Patch: fix_sensitive_dirs_linux ==="
  echo &"  Target: {filePath}"
  if not fileExists(filePath):
    echo &"  [FAIL] File not found: {filePath}"
    quit(1)
  let input = readFile(filePath)
  let output = apply(input)
  if output != input:
    writeFile(filePath, output)
    echo "  [PASS] Linux sensitive dirs patched successfully"
  else:
    echo "  [PASS] No changes needed (already patched)"
