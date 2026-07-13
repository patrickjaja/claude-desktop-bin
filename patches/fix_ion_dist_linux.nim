# @patch-target: resources/ion-dist
# @patch-type: nim-dir
#
# Patch the ion-dist 3P configuration SPA for Linux compatibility.
#
# The ion-dist bundle is a React SPA served via the app:// protocol that
# powers Developer -> Configure Third-Party Inference. It has two issues
# on Linux:
#
#   1) The org-plugins mount path only has mac/win entries - on Linux it
#      falls back to the macOS path "/Library/Application Support/Claude/org-plugins"
#
#   2) The mount-path display component uses VAR===ENUM.Win32?X.win:X.mac
#      which ignores the Linux case entirely
#
# The target JS file has a content-hash filename (e.g. c71860c77-C6hxWuPG.js)
# that changes every upstream release. This patch finds the file by grepping
# for the unique mountPath pattern.

import std/[os, strutils]
import regex

const EXPECTED_PATCHES = 2

proc findTargetFile(ionDistDir: string): string =
  for dir in walkDir(ionDistDir / "assets" / "v1"):
    if dir.kind == pcFile and dir.path.endsWith(".js"):
      let content = readFile(dir.path)
      if content.contains(
        """mountPath:{mac:"/Library/Application Support/Claude/org-plugins"""
      ):
        return dir.path
  return ""

proc apply(filePath: string): int =
  var content = readFile(filePath)
  let original = content
  var patchesApplied = 0

  # Sub-patch A: Add linux key to the mountPath object
  let oldMountPath =
    """mountPath:{mac:"/Library/Application Support/Claude/org-plugins",win:"%ProgramFiles%\\Claude\\org-plugins"}"""
  let newMountPath =
    """mountPath:{mac:"/Library/Application Support/Claude/org-plugins",win:"%ProgramFiles%\\Claude\\org-plugins",linux:"/etc/claude-desktop/org-plugins"}"""

  if content.contains(newMountPath):
    echo "  [OK] org-plugins linux path: already applied"
    patchesApplied += 1
  elif content.contains(oldMountPath):
    content = content.replace(oldMountPath, newMountPath)
    echo "  [OK] org-plugins linux path: 1 match"
    patchesApplied += 1
  else:
    echo "  [FAIL] org-plugins linux path: pattern not found"

  # Sub-patch B: Fix mount-path display to use linux path when on Linux.
  # Variable names are minified and change between versions:
  #   v1.7196: r===W.Win32?t.win:t.mac
  #   v1.8089: C===V.Win32?Ve.mountPath.win:Ve.mountPath.mac
  # Use [\w$.]+ wildcards to match any variable/property chain.
  let alreadyPatchedPat =
    re2"""[\w$]+=== *[\w$]+\.Win32\?[\w$.]+\.win:[\w$]+=== *[\w$]+\.Linux\?[\w$.]+\.linux:[\w$.]+\.mac"""
  var alreadyB = false
  for m in content.findAll(alreadyPatchedPat):
    alreadyB = true
    break

  if alreadyB:
    echo "  [OK] mount path platform ternary: already applied"
    patchesApplied += 1
  else:
    let ternaryPat =
      re2"""([\w$]+)=== *([\w$]+)\.Win32\?([\w$.]+)\.win:([\w$.]+)\.mac"""
    var countB = 0
    content = content.replace(
      ternaryPat,
      proc(m: RegexMatch2, s: string): string =
        inc countB
        let condVar = s[m.group(0)]
        let enumVar = s[m.group(1)]
        let winObj = s[m.group(2)]
        let macObj = s[m.group(3)]
        condVar & "===" & enumVar & ".Win32?" & winObj & ".win:" & condVar & "===" &
          enumVar & ".Linux?" & winObj & ".linux:" & macObj & ".mac",
    )
    if countB >= 1:
      echo "  [OK] mount path platform ternary: " & $countB & " match"
      patchesApplied += 1
    else:
      echo "  [FAIL] mount path platform ternary: pattern not found"

  if patchesApplied < EXPECTED_PATCHES:
    echo "  [FAIL] Only " & $patchesApplied & "/" & $EXPECTED_PATCHES &
      " patches applied"
    return 1

  if content != original:
    writeFile(filePath, content)
    echo "  [PASS] All " & $EXPECTED_PATCHES & " patches applied"
  else:
    echo "  [PASS] Already patched (no changes needed)"
  return 0

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_ion_dist_linux <ion-dist-directory>"
    quit(1)
  let ionDistDir = paramStr(1)
  echo "=== Patch: fix_ion_dist_linux ==="
  echo "  Target dir: " & ionDistDir
  if not dirExists(ionDistDir):
    echo "  [FAIL] Directory not found: " & ionDistDir
    quit(1)
  let targetFile = findTargetFile(ionDistDir)
  if targetFile == "":
    echo "  [FAIL] Could not find target JS file with mountPath pattern in " & ionDistDir
    echo "  [INFO] This likely means the upstream changed the 3P config UI structure"
    quit(1)
  echo "  Target file: " & extractFilename(targetFile)
  let exitCode = apply(targetFile)
  quit(exitCode)
