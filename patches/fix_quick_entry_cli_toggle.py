#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Enable `claude-desktop --toggle-quick-entry` CLI trigger for Quick Entry.

On GNOME Wayland the xdg-desktop-portal GlobalShortcuts path is unreliable —
users commonly don't see or dismiss the approval notification, and Electron's
globalShortcut.register() returns true in both cases. This patch makes the
already-running Claude process respond to a CLI argv trigger, so users can
bypass the portal by binding any compositor-level key (e.g. via `gsettings`)
to `claude-desktop --toggle-quick-entry`.

Three sub-patches:

A. Capture the Quick Entry show handler into globalThis.__ceQuickEntryShow.
   Anchor: the literal `.QUICK_ENTRY` enum property name inside the handler
   registration. That property name survives re-minification; the surrounding
   function name (XYe), enum variable (Iw), and main-window variable (Ct) do
   not, so we capture them with [\\w$]+.

B. Prepend an argv check to the app.on("second-instance", ...) handler.
   Anchor: the literal "second-instance" event name (Electron API surface,
   stable). When --toggle-quick-entry is in argv, invoke the captured handler
   and return early — don't fall through to the upstream main-window show.

C. First-instance path: when Claude isn't already running and the launcher
   was invoked with --toggle-quick-entry, requestSingleInstanceLock() wins
   and no second-instance fires. Schedule a one-shot check after the handler
   is captured so Quick Entry opens once the app is ready.

The patch fails soft end-to-end: if the global hasn't been captured (e.g.
sub-patch A silently regressed after re-minification), the second-instance
pre-check falls through to upstream behavior (main window show).

Usage: python3 fix_quick_entry_cli_toggle.py <path_to_index.js>
"""

import sys
import os
import re


# Flag literal used by both the launcher and patches. Keep in sync with
# scripts/claude-desktop-launcher.sh. The exact string is embedded into
# the patched JS; changing it requires re-patching.
TRIGGER_FLAG = "--toggle-quick-entry"

# Global name used to bridge the captured handler (A) to its invokers
# (B and C). Prefixed to avoid collisions with minified vars.
HANDLER_GLOBAL = "__ceQuickEntryShow"


def patch_cli_toggle(filepath):
    """Apply the three CLI-toggle sub-patches."""

    print("=== Patch: fix_quick_entry_cli_toggle ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, "rb") as f:
        content = f.read()

    original_content = content
    applied = 0
    EXPECTED = 3

    # ------------------------------------------------------------------
    # Sub-patch A: capture handler into globalThis.__ceQuickEntryShow
    # ------------------------------------------------------------------
    # Target (v1.3109.0):
    #   XYe(Iw.QUICK_ENTRY,()=>{Ct&&!Ct.isDestroyed()&&Ct.isFullScreen()?(Ct.focus(),pce()):tWt()})
    #
    # We replace the inner arrow expression with an assignment so the
    # function is both passed to XYe and stored globally. Also append a
    # scheduled check for first-instance argv (sub-patch C, same match).
    #
    # Idempotency: if HANDLER_GLOBAL already appears in the file we assume
    # the patch was applied previously — skip but count as success.

    if HANDLER_GLOBAL.encode("utf-8") in content:
        print(f"  [INFO] {HANDLER_GLOBAL} already present — sub-patch A/C skipped")
        applied += 2  # A + C together
    else:
        # Capture groups:
        #   1: register-fn name (e.g. XYe)
        #   2: enum var name (e.g. Iw)
        #   3: full arrow function text `()=>{ ... }`
        pat_a = re.compile(
            rb"([\w$]+)"  # 1: register fn
            rb"\("
            rb"([\w$]+)\.QUICK_ENTRY,"  # 2: enum var
            rb"(\(\)=>\{[\w$]+&&![\w$]+\.isDestroyed\(\)&&[\w$]+\.isFullScreen\(\)\?\([\w$]+\.focus\(\),[\w$]+\(\)\):[\w$]+\(\)\})"  # 3: arrow fn
            rb"\)"
        )

        def repl_a(m):
            reg_fn = m.group(1)
            enum_var = m.group(2)
            arrow = m.group(3)
            # Parse the arrow function body out of the matched text so we
            # can wrap it with a debounce guard. The matched arrow has the
            # exact form `()=>{<body>}` — strip the braces and re-wrap.
            assert arrow.startswith(b"()=>{") and arrow.endswith(b"}"), f"unexpected arrow shape: {arrow!r}"
            body = arrow[len(b"()=>{") : -1]

            # A: register with assignment to globalThis AND a debounce guard.
            #
            # Why the debounce: on GNOME Wayland we observed the launcher /
            # compositor delivering `second-instance` twice ~500 ms apart
            # for a single Ctrl+Alt+Space press. (Empirical: timestamps
            # 39943 and 40443 for one CLI invocation.) Each invocation goes
            # through upstream U$t(), which implements toggle semantics —
            # `IHA && Po.isVisible() ? EHA(null) : show...`. The second
            # fire saw Po visible and dismissed it via kjA() → Po.blur() +
            # Po.hide(), producing the "flashes open, closes" symptom.
            #
            # A 900 ms debounce is wider than the observed 500 ms
            # double-fire and still narrow enough that a deliberate
            # user-driven second press (to toggle-close the window) after
            # a legitimate pause still works.
            arrow_wrapped = b"()=>{var __t=Date.now();if(globalThis.__ceQEInvokedAt&&__t-globalThis.__ceQEInvokedAt<900)return;globalThis.__ceQEInvokedAt=__t;" + body + b"}"
            assign = b"globalThis." + HANDLER_GLOBAL.encode("utf-8") + b"=" + arrow_wrapped
            # C: schedule a one-shot argv check for first-instance launches.
            # Runs after handler capture. 500ms lets the main window finish
            # coming up; inside tWt() there's a guard that focuses the main
            # window first if it's fullscreen, so this is safe even if the
            # main window is still settling.
            #
            # IMPORTANT: the original XYe(...) call sits inside a
            # comma-separated expression chain (e.g. `...,hvr(),XYe(...),...`),
            # so we must use `,` not `;` — a semicolon here would close the
            # surrounding expression and break the next sub-expression.
            first_instance = (
                b",setTimeout(()=>{"
                b'try{if(Array.isArray(process.argv)&&process.argv.includes("'
                + TRIGGER_FLAG.encode("utf-8")
                + b'")&&globalThis.'
                + HANDLER_GLOBAL.encode("utf-8")
                + b")globalThis."
                + HANDLER_GLOBAL.encode("utf-8")
                + b"()}catch(e){}"
                b"},500)"
            )
            return reg_fn + b"(" + enum_var + b".QUICK_ENTRY," + assign + b")" + first_instance

        content, count_a = pat_a.subn(repl_a, content)
        if count_a == 1:
            print("  [OK] sub-patch A (handler capture) + C (first-instance schedule) applied")
            applied += 2
        elif count_a > 1:
            print(f"  [FAIL] sub-patch A matched {count_a} times (expected 1)")
            return False
        else:
            print("  [FAIL] sub-patch A did not match QUICK_ENTRY handler registration")
            return False

    # ------------------------------------------------------------------
    # Sub-patch B: prepend argv check to second-instance handler
    # ------------------------------------------------------------------
    # Target (v1.3109.0):
    #   wA.app.on("second-instance",(A,t,i)=>{if(mB())return;Ct&&!Ct.isDestroyed()&&(...)})
    #
    # Capture the arg names so we can reference argv (2nd arg) in the
    # injected check. Fails soft: if HANDLER_GLOBAL wasn't captured we
    # still fall through to upstream behavior.

    # Idempotency marker — a literal from the injected code that upstream
    # would never write. If it's already in the file, this patch ran once.
    b_marker = b'"' + TRIGGER_FLAG.encode("utf-8") + b'")){try{globalThis.'
    if b_marker in content:
        print("  [INFO] sub-patch B already applied — skipped")
        applied += 1
    else:
        pat_b = re.compile(
            rb'(\.on\("second-instance",\()'  # 1: `.on("second-instance",(`
            rb"([\w$]+),([\w$]+),([\w$]+)"  # 2,3,4: arg names (event, argv, cwd)
            rb"(\)=>\{)"  # 5: `)=>{`
        )

        def repl_b(m):
            head = m.group(1)
            _evt = m.group(2)
            argv = m.group(3)
            _cwd = m.group(4)
            tail = m.group(5)
            check = (
                b"if(Array.isArray("
                + argv
                + b")&&"
                + argv
                + b'.includes("'
                + TRIGGER_FLAG.encode("utf-8")
                + b'"))'
                + b"{try{globalThis."
                + HANDLER_GLOBAL.encode("utf-8")
                + b"&&globalThis."
                + HANDLER_GLOBAL.encode("utf-8")
                + b"()}catch(e){}return}"
            )
            return head + m.group(2) + b"," + argv + b"," + m.group(4) + tail + check

        content, count_b = pat_b.subn(repl_b, content)
        if count_b == 1:
            print("  [OK] sub-patch B (second-instance argv check) applied")
            applied += 1
        elif count_b > 1:
            print(f"  [FAIL] sub-patch B matched {count_b} times (expected 1)")
            return False
        else:
            print('  [FAIL] sub-patch B did not match .on("second-instance", ...) handler')
            return False

    # ------------------------------------------------------------------
    # Summary
    # ------------------------------------------------------------------
    if applied < EXPECTED:
        print(f"  [FAIL] Only {applied}/{EXPECTED} sub-patches applied")
        return False

    if content != original_content:
        with open(filepath, "wb") as f:
            f.write(content)
        print(f"  [PASS] {applied}/{EXPECTED} sub-patches applied")
        return True
    else:
        print(f"  [PASS] No changes needed — already patched ({applied}/{EXPECTED})")
        return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_cli_toggle(sys.argv[1])
    sys.exit(0 if success else 1)
