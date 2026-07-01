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
    #     ...process.platform==="win32"?[...,"PowerShell")]:[]
    #   ],<nextVar>=[...]
    #
    # In the minified JS this looks like:
    #   ...("OneDrive","Documents","PowerShell")]:[]],<nextVar>=[...
    #
    # We want to inject BEFORE the outer ] that closes the sensitive-dirs array:
    #   ...("OneDrive","Documents","PowerShell")]:[],...linux?[...]:[]],<nextVar>=[...
    #
    # v1.13576.0: the next var after the array used to be the `.zshrc` shell-rc
    # array, but upstream inserted two new arrays between them (`["Scheduled",
    # "Artifacts"]` and a scheduled-tasks/agents/... array). The win32 block
    # still ends with the same `"PowerShell")]:[]` close, which is unique in
    # the bundle, so anchor on that instead of on `.zshrc`.
    #
    # Regex breakdown:
    #   ("PowerShell"\)\]:\[\]) - group 0: last win32 path + win32-array close
    #                             + ternary empty-fallback ":[]"
    #   (\];)                    - group 1: the outer sensitive-dirs array close
    #                             FOLLOWED BY ';'
    #
    # DISAMBIGUATION (important): the bare `"PowerShell")]:[]]` shape occurs TWICE
    # in v1.17377 — once at the intended sensitive-dirs array (`Xdn`), and once at
    # an unrelated per-home-root array (`eLn=[...flatMap(A=>[j.join(A,...)])]`). The
    # intended site is uniquely followed by `];function ...` (statement end), while
    # the unrelated `eLn` site is followed by `]),...flatMap` (expression continues).
    # nim's string.replace is GLOBAL, so anchoring only on `]` would inject the
    # Linux dirs into BOTH — polluting `eLn` (which holds only absolute j.join()
    # paths) with 3 bare relative strings. Requiring the trailing `;` restricts the
    # match to the correct sensitive-dirs array. EXPECT EXACTLY ONE match.
    let pattern = re2"""("PowerShell"\)\]:\[\])(\];)"""

    var count = 0
    result = result.replace(
      pattern,
      proc(m: RegexMatch2, s: string): string =
        inc count
        # Reconstruct: win32 fallback + Linux spread + outer array close + ';'
        s[m.group(0)] & LINUX_DIRS_SPREAD & s[m.group(1)],
    )
    if count == 1:
      echo &"  [OK] Linux sensitive dirs injected: {count} match(es)"
      patchesApplied += 1
    elif count == 0:
      echo "  [FAIL] Could not find sensitive-dirs array closing pattern"
      echo "  [HINT] Search for '.ssh' near '.aws' and '.gnupg' in the target file"
    else:
      echo &"  [FAIL] Expected exactly 1 sensitive-dirs match, got {count} — anchor now matches an unintended array; re-audit (see disambiguation note above)"

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
