#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Make the Quick Entry accelerator preference (`quickEntryShortcut`) actually
take effect on Linux.

Symptom: on Linux the Settings UI lets the user pick a Quick Entry
accelerator, but changing it has no effect — the shortcut is stuck on the
hardcoded default (Ctrl+Alt+Space / Alt+Space on GNOME).

Root cause: the upstream bundle contains a guard roughly like:

    if (((u = J0().nativeQuickEntry) == null ? void 0 : u.status) !== "supported")
        // --- legacy branch ---
        di("legacyQuickEntryEnabled") && Xb(Iw.QUICK_ENTRY, zdA()),
        Zw.on("legacyQuickEntryEnabled", B => { Xb(Iw.QUICK_ENTRY, B ? zdA() : null) });
    else {
        // --- accelerator branch ---
        const B = d => {
            if (d === "off" || d === "double-tap-option") Xb(Iw.QUICK_ENTRY, null);
            else Xb(Iw.QUICK_ENTRY, d.accelerator) && cs("quickEntryShortcut", ...);
        };
        B(di("quickEntryShortcut"));
        Zw.on("quickEntryShortcut", B);
        ...
    }

`J0().nativeQuickEntry` is produced by a function that returns
`{status:"unavailable"}` on any non-darwin platform (`process.platform !==
"darwin"`), so on Linux the first branch always runs. That branch reads
only the `legacyQuickEntryEnabled` boolean pref and wires up the hardcoded
default accelerator — it ignores `quickEntryShortcut` entirely. The else
branch is the one that honours the user's chosen accelerator and calls
`Xb(Iw.QUICK_ENTRY, d.accelerator)` — which is exactly the same
`wA.globalShortcut.register(...)` path, the one that routes through
Chromium's `GlobalShortcutsPortal` on Wayland/GNOME. That's what we want.

Fix: rewrite the guard so Linux (and every non-darwin platform) always
takes the else branch. On darwin we preserve the original behaviour —
the native overlay path matters there and we don't want to mis-wire
`optionDoubleTapped`.

    Before:  if ((ORIG_EXPR))
    After:   if (process.platform==="darwin"&&(ORIG_EXPR))

On darwin `process.platform==="darwin"` is true, so the overall condition
reduces to ORIG_EXPR and behaviour is identical. On Linux it's false, so
the whole `if` is false and control falls through to the else branch —
which reads `quickEntryShortcut` and registers the user's accelerator.

We do NOT modify the Fvr() producer itself (it's the macOS Swift overlay
bridge used for `optionDoubleTapped`), we do NOT change the default
accelerator zdA(), and we do NOT touch the bodies of either branch.

Usage: python3 fix_quick_entry_shortcut_linux.py <path_to_index.js>
"""

import sys
import os
import re


def patch_shortcut_linux(filepath):
    """Un-gate the Quick Entry accelerator branch on non-darwin platforms."""

    print("=== Patch: fix_quick_entry_shortcut_linux ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, "rb") as f:
        content = f.read()

    original_content = content
    applied = 0
    EXPECTED = 1

    # Idempotency: detect our marker (`process.platform==="darwin"&&`
    # preceding — directly or via an extra `(` wrapper — the
    # `(<var>=<fn>().nativeQuickEntry` probe) and treat as already patched.
    #
    # Our replacement wraps ORIG_EXPR in `(...)`, producing
    #   process.platform==="darwin"&&(((u=J0()....nativeQuickEntry)...)
    # so the look-ahead must tolerate one or more `(` between the `&&` and
    # the `(<var>=...` sub-expression.
    idem = re.compile(
        rb'process\.platform==="darwin"&&\(*'
        rb'\(\([\w$]+=[\w$]+\(\)\.nativeQuickEntry\)==null\?void 0:'
        rb'[\w$]+\.status\)!=="supported"'
    )
    if idem.search(content):
        print('  [INFO] process.platform==="darwin"&& guard already in place — skipped')
        return True

    # Target (v1.3109.0):
    #   ((u=J0().nativeQuickEntry)==null?void 0:u.status)!=="supported"
    #
    # Anchors:
    #   - the literal `.nativeQuickEntry)==null?void 0:`
    #   - the literal `.status)!=="supported"`
    # Captures:
    #   1: the temp var (e.g. `u`) assigned from the producer call
    #   2: the producer fn name (e.g. `J0`)
    #   3: the temp var re-read for `.status` (same as #1 in current minifier
    #      output, but captured independently so a future rename of only one
    #      occurrence still matches)
    pat = re.compile(
        rb'\(\(([\w$]+)=([\w$]+)\(\)\.nativeQuickEntry\)==null\?void 0:'
        rb'([\w$]+)\.status\)!=="supported"'
    )

    matches = pat.findall(content)
    if len(matches) == 0:
        print("  [FAIL] nativeQuickEntry supported-guard pattern not found")
        return False
    if len(matches) > 1:
        print(f"  [FAIL] pattern matched {len(matches)} times (expected 1)")
        return False

    def repl(m):
        orig = m.group(0)
        return b'process.platform==="darwin"&&(' + orig + b')'

    content, count = pat.subn(repl, content)
    if count == 1:
        print('  [OK] guard rewritten: else-branch now reached on non-darwin')
        applied += 1
    else:
        # Should be unreachable given the findall check above, but keep the
        # strict contract: anything other than exactly 1 replacement fails.
        print(f"  [FAIL] subn replaced {count} occurrences (expected 1)")
        return False

    if applied < EXPECTED:
        print(f"  [FAIL] Only {applied}/{EXPECTED} applied")
        return False

    if content != original_content:
        with open(filepath, "wb") as f:
            f.write(content)
        print(f"  [PASS] {applied}/{EXPECTED} applied")
        return True
    else:
        print(f"  [PASS] No changes needed — already patched ({applied}/{EXPECTED})")
        return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_shortcut_linux(sys.argv[1])
    sys.exit(0 if success else 1)
