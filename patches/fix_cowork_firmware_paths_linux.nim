# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
#
# Make the Cowork VM capability probe find OVMF firmware + virtiofsd on the
# distros Anthropic's official Debian .deb does not target (Arch, Fedora/RHEL,
# openSUSE, NixOS, ...).
#
# The official build hard-codes DEBIAN-ONLY firmware paths. The capability probe
# builds {qemuPath, firmwarePath, virtiofsdPath, ...} and the support determiner
# returns "unsupported" (reason: "Cowork requires QEMU...") whenever ANY of them
# is null. On Arch, edk2-ovmf installs OVMF to /usr/share/edk2/x64/OVMF_CODE.4m.fd,
# NOT the Debian /usr/share/OVMF/OVMF_CODE_4M.fd, so firmwarePath resolves to null
# and Cowork is permanently "unsupported" -> the Download button is inert and the
# workspace never provisions.  (qemuPath is a $PATH lookup, so it works anywhere
# qemu-system-x86_64 is installed; virtiofsd is bundled, so it also resolves.)
#
# Upstream code (minified var names change every release):
#   boi = process.arch==="arm64"
#           ? ["/usr/share/AAVMF/AAVMF_CODE.fd"]
#           : ["/usr/share/OVMF/OVMF_CODE_4M.fd","/usr/share/OVMF/OVMF_CODE.fd"],
#   Loi = ["/usr/libexec/virtiofsd","/usr/bin/virtiofsd"]
#
# The firmware resolver i_t(boi) returns the FIRST readable path, and the _VARS
# companion is derived by s.replace("OVMF_CODE","OVMF_VARS") / ("AAVMF_CODE",
# "AAVMF_VARS"), so every CODE path we add must have a matching VARS file with the
# same name shape next to it (true for the distro paths below).
#
# We extend BOTH arrays with distro-portable candidates. Order does not matter for
# correctness (resolver takes the first that exists) but Debian paths are kept
# FIRST so behaviour on Debian/Ubuntu is byte-for-byte unchanged.

import std/[os, strutils]
import regex

proc apply*(input: string): string =
  result = input

  # Additional x86_64 OVMF_CODE candidates for non-Debian distros.
  # The app derives the VARS path by A.replace("OVMF_CODE","OVMF_VARS"), so a
  # candidate is only usable if (a) the CODE file exists on that distro AND
  # (b) a sibling file with "OVMF_CODE" -> "OVMF_VARS" in its name also exists.
  # Every path below satisfies both (verified: Arch live box; Fedora/RHEL via
  # edk2-ovmf package file-list). Distros whose firmware is named "*-code.bin"
  # (openSUSE: /usr/share/qemu/ovmf-x86_64-code.bin) or "edk2-x86_64-code.fd"
  # (generic qemu symlinks) are deliberately NOT added: the OVMF_CODE->OVMF_VARS
  # replace would not yield their real VARS filename, so they'd resolve as
  # firmwarePath but fail later at VARS lookup. Covering them needs a separate
  # "-code"->"-vars" rule; tracked as a known gap, not added here.
  const extraX64 =
    "\"/usr/share/edk2/ovmf/OVMF_CODE.fd\"," &
      # Fedora 40+/RHEL 9+ (edk2-ovmf; VARS: OVMF_VARS.fd)
    "\"/usr/share/edk2/x64/OVMF_CODE.4m.fd\"," &
      # Arch (edk2-ovmf; VARS: OVMF_VARS.4m.fd)
    "\"/usr/share/edk2/x64/OVMF_CODE.fd\"," # Arch alt/older name if present

  # aarch64 needs NO additions: the Debian path the app already checks,
  # /usr/share/AAVMF/AAVMF_CODE.fd (+ AAVMF_VARS.fd), is ALSO the canonical
  # path on Fedora/RHEL (edk2-aarch64) and Arch (edk2-aarch64). Only openSUSE
  # differs (aavmf-aarch64-code.bin), which has the same "-code.bin" VARS-replace
  # problem as its x86_64 firmware and is left as the same known gap.

  # Additional virtiofsd system-path candidates. The app checks
  # /usr/libexec/virtiofsd (Fedora/RHEL/openSUSE) and /usr/bin/virtiofsd. NOTE
  # (verified v1.17377.1): the BUNDLED resources/virtiofsd is only used as a
  # fallback on Ubuntu 22.x (`os-release id==="ubuntu" && versionId.startsWith
  # ("22.")`), where apt has no standalone Rust virtiofsd - on every other
  # distro a missing system virtiofsd means "unsupported". So a system virtiofsd
  # (our optdepends/Recommends) is REQUIRED outside Ubuntu 22.04, and we add
  # Arch's /usr/lib/virtiofsd so the probe finds it there.
  const extraVirtiofsd =
    "\"/usr/lib/virtiofsd\"," & # Arch (virtiofsd pkg)
    "\"/usr/lib/qemu/virtiofsd\"," # some distros

  var patchesApplied = 0
  const EXPECTED_PATCHES = 2 # A: firmware arrays, B: virtiofsd array

  # --- Patch A: extend the x86_64 OVMF firmware array ------------------------
  # Only the x86_64 (OVMF) array needs extending; the aarch64 (AAVMF) array's
  # single Debian path is already correct on every distro we support (see above).
  # We anchor on the x64 array open `["` immediately followed by the first Debian
  # value, and splice our fully-quoted candidates in right after the `[`.
  # Anchoring on `]:[` (the ternary's arm-array close + x64-array open) makes the
  # match unambiguous even though "/usr/share/OVMF/OVMF_CODE_4M.fd" is short.
  # group0 = `]:[`   group1 = `"/usr/share/OVMF/OVMF_CODE_4M.fd"`  (x64 first value)
  let firmwarePattern = re2"""(\]:\[)("/usr/share/OVMF/OVMF_CODE_4M\.fd")"""
  var countA = 0
  let alreadyFirmware = "/usr/share/edk2/x64/OVMF_CODE.4m.fd" in result
  if alreadyFirmware:
    echo "  [OK] firmware paths: non-Debian OVMF candidates already present"
    inc patchesApplied
  else:
    result = result.replace(
      firmwarePattern,
      proc(m: RegexMatch2, s: string): string =
        inc countA
        s[m.group(0)] & extraX64 & s[m.group(1)],
    )
    if countA == 1:
      echo "  [OK] firmware paths: injected non-Debian OVMF candidates"
      inc patchesApplied
    else:
      echo "  [FAIL] firmware paths: expected 1 match, got " & $countA &
        " (upstream OVMF array shape changed - re-anchor)"

  # --- Patch B: extend the virtiofsd system-path array -----------------------
  # group0 = `["/usr/libexec/virtiofsd",`   group1 = `"/usr/bin/virtiofsd"`
  let virtiofsdPattern = re2"""(\["/usr/libexec/virtiofsd",)("/usr/bin/virtiofsd")"""
  var countB = 0
  let alreadyVirtiofsd = "/usr/lib/virtiofsd" in result
  if alreadyVirtiofsd:
    echo "  [OK] virtiofsd paths: non-Debian candidate already present"
    inc patchesApplied
  else:
    result = result.replace(
      virtiofsdPattern,
      proc(m: RegexMatch2, s: string): string =
        inc countB
        # group0: ["/usr/libexec/virtiofsd","   group1: /usr/bin/virtiofsd"
        s[m.group(0)] & extraVirtiofsd & s[m.group(1)],
    )
    if countB == 1:
      echo "  [OK] virtiofsd paths: injected non-Debian candidate"
      inc patchesApplied
    else:
      echo "  [FAIL] virtiofsd paths: expected 1 match, got " & $countB &
        " (upstream virtiofsd array shape changed - re-anchor)"

  if patchesApplied < EXPECTED_PATCHES:
    echo "  [FAIL] Only " & $patchesApplied & "/" & $EXPECTED_PATCHES &
      " patches applied"
    quit(1)

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_cowork_firmware_paths_linux <path_to_index.js>"
    quit(1)
  let filePath = paramStr(1)
  echo "=== Patch: fix_cowork_firmware_paths_linux ==="
  echo "  Target: " & filePath
  if not fileExists(filePath):
    echo "  [FAIL] File not found: " & filePath
    quit(1)
  let input = readFile(filePath)
  let output = apply(input)
  if output != input:
    writeFile(filePath, output)
    echo "  [PASS] All required patterns matched and applied"
  else:
    echo "  [OK] No changes made (already patched)"
