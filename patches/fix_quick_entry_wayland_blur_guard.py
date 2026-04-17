#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Guard the Quick Entry blur-to-dismiss handler against spurious blurs
on Wayland.

Symptom (issue #38, reproduced on Ubuntu / GNOME 48 Wayland and reported
on Fedora 43 / GNOME 49): user presses Ctrl+Alt+Space, the Quick Entry
window flashes visible, then disappears before they can type anything.

Root cause: when `Po.show()` is called from a background context, GNOME
Mutter's focus-stealing prevention declines to transfer focus to the new
window. No `focus` event fires. But Electron still emits spurious `blur`
events (because the logical focus state changed from "someone else was
focused" to "Po is visible but not focused" — Chromium interprets that as
a blur). Upstream:

    Po.on("blur", () => { EHA(null) })

dismisses immediately on any blur. Net result on GNOME Wayland: Po shown
one frame, dismissed before user can interact.

**Strategy: only dismiss on blur if Po was actually focused first.**

If `focus` never fired, then by definition Po never had focus to lose, so
the blur is a phantom and we ignore it. If `focus` fired (X11, KDE
Plasma, Hyprland all succeed here), subsequent `blur` means the user
genuinely clicked away, so normal dismiss behavior kicks in.

Implementation — four small listeners replace the single
`Po.on("blur", () => EHA(null))`:

    Po.on("focus", () => { globalThis.__ceQEFocused = true })
    Po.on("blur",  () => { if (!globalThis.__ceQEFocused) return;
                           globalThis.__ceQEFocused = false;
                           EHA(null) })
    Po.on("show",  () => { globalThis.__ceQEFocused = false })
    Po.on("hide",  () => { globalThis.__ceQEFocused = false })

Escape / submit paths are unaffected — those go through `requestDismiss` /
`requestDismissWithPayload` IPC, which call EHA directly without touching
the blur event. So even on GNOME Wayland where Po never gains focus and
blur never dismisses, the user can still close the window with Escape.

We intentionally use `globalThis` rather than a closure variable so the
state persists across Po re-creation (Po is torn down and recreated on
certain paths). Prefix `__ceQE` to avoid collision with any upstream
variables (upstream's minifier doesn't generate names with underscores).

Usage: python3 fix_quick_entry_wayland_blur_guard.py <path_to_index.js>
"""

import sys
import os
import re


# Shared global used by the focus-tracked blur handler. Distinct from
# `__ceQuickEntryShow` (from fix_quick_entry_cli_toggle.py) so the patches
# don't accidentally collide.
FOCUS_GLOBAL = "__ceQEFocused"


def patch_blur_guard(filepath):
    """Replace Po.on("blur", ...) with a focus-tracked variant."""

    print("=== Patch: fix_quick_entry_wayland_blur_guard ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, "rb") as f:
        content = f.read()

    original_content = content
    applied = 0
    EXPECTED = 1

    # Idempotency: if our marker global is already present we've run once.
    if FOCUS_GLOBAL.encode("utf-8") in content:
        print(f"  [INFO] {FOCUS_GLOBAL} already present — skipped")
        return True

    # Target (v1.3109.0):
    #   Po.on("blur",()=>{EHA(null)})
    #
    # Captures:
    #   1: Quick Entry window var name (e.g. Po — minified, may change)
    #   2: dismiss fn name (e.g. EHA — minified)
    #
    # The `"blur"` string literal + the `\)=>\{` arrow + `\(null\)` tail
    # are the stable anchors. `EHA` is captured but used only as the call
    # target inside the replacement — we preserve whatever minified name
    # upstream chose.
    pat = re.compile(
        rb'([\w$]+)\.on\("blur",'     # 1: Po
        rb'\(\)=>\{'
        rb'([\w$]+)\(null\)'           # 2: EHA
        rb'\}\)'
    )

    def repl(m):
        win = m.group(1)  # Po
        fn = m.group(2)   # EHA
        fg = FOCUS_GLOBAL.encode("utf-8")
        # Replace the single blur listener with four listeners that
        # collectively track whether Po ever gained focus before a blur.
        # If it didn't, the blur is a phantom (Wayland activation race)
        # and we ignore it.
        return (
            win + b'.on("focus",()=>{globalThis.' + fg + b"=!0}),"
            + win + b'.on("blur",()=>{'
              b"if(!globalThis." + fg + b")return;"
              b"globalThis." + fg + b"=!1;"
              + fn + b"(null)"
            + b"}),"
            + win + b'.on("show",()=>{globalThis.' + fg + b"=!1}),"
            + win + b'.on("hide",()=>{globalThis.' + fg + b"=!1})"
        )

    content, count = pat.subn(repl, content)
    if count == 1:
        print("  [OK] blur handler replaced with focus-tracked variant")
        applied += 1
    elif count > 1:
        print(f"  [FAIL] pattern matched {count} times (expected 1)")
        return False
    else:
        print('  [FAIL] pattern did not match Po.on("blur", () => EHA(null))')
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

    success = patch_blur_guard(sys.argv[1])
    sys.exit(0 if success else 1)
