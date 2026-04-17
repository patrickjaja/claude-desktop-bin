#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Make computer-use work on Linux by removing platform gates and providing a Linux executor.

Two runtime behaviors are available. Selection precedence:

  1. CLAUDE_CU_MODE=<regular|kwin-wayland>          (explicit override)
  2. XDG_SESSION_DESKTOP=KDE + XDG_SESSION_TYPE=wayland + kwin-portal-bridge
     on PATH (or KWIN_PORTAL_BRIDGE_BIN set)        → auto kwin-wayland
  3. Anything else                                  → regular

  CLAUDE_CU_MODE=regular
    Cross-distro inline executor built from xdotool/ydotool/scrot/grim/portal/
    spectacle/gdbus/desktopCapturer with session-aware detection
    (XDG_SESSION_TYPE, SWAYSOCK, HYPRLAND_INSTANCE_SIGNATURE, XDG_CURRENT_DESKTOP).
    handleToolCall is rerouted through a hybrid dispatcher that services normal
    CU tools directly via __linuxExecutor while teach tools fall through to the
    upstream chain. Teach overlay uses Electron BrowserWindow with VM-aware
    transparency + setIgnoreMouseEvents no-op workaround.

  CLAUDE_CU_MODE=kwin-wayland
    KDE-targeted executor loaded from js/executor_linux.js (kwin-portal-
    bridge backed). handleToolCall stays on the upstream path so the normal
    MCP flow exercises the executor for allowlists, frontmost checks,
    screenshot coordinate scaling, etc. Teach overlay + side-panel are routed
    through bridge-backed controllers (__initTeachController, __initDockController).
    Adds plasmashell/Dolphin aliasing + explicit Linux/KDE system-prompt wording.

Shared patches (always applied regardless of mode):
  * ese Set += "linux"                    → vee()/rj() accept Linux
  * createDarwinExecutor                  → returns globalThis.__linuxExecutor
  * ensureOsPermissions                   → {granted:true} on Linux (skip TCC)
  * mVt()/rj()                            → force true on Linux
  * cu lock acquire/release               → __setLockHeld hook (kwin-only code,
                                             optional chaining makes it a no-op
                                             in regular mode)
  * screenshot intro note workaround      → linuxVisibleLastScreenshot closure
  * teach overlay mouse / VM / display    → BrowserWindow workarounds (regular-only
                                             effect; kwin-wayland returns early via
                                             __initTeachController capability check)

Runtime text patches use a 3-way ternary:
    platform==="linux"
      ? ((process.env.CLAUDE_CU_MODE||"regular")==="kwin-wayland" ? KDE : generic)
      : macOS

Usage: python3 fix_computer_use_linux.py <path_to_index.js>
"""

import sys
import os
import re


# Linux executor — implements the same interface as createDarwinExecutor's return value.
# Only the low-level operations are replaced; upstream dispatches to these methods.
#
# Note: execSync is used intentionally for xdotool/scrot/xrandr — these are
# hardcoded system commands, not user-controlled input.
_CU_HERE = os.path.dirname(os.path.abspath(__file__))
with open(os.path.join(_CU_HERE, "../js/cu_linux_executor.js"), "r", encoding="utf-8") as _f:
    LINUX_EXECUTOR_JS = _f.read()


# Linux hybrid handler — injected at the top of handleToolCall as an early-return block.
#
# Architecture:
#   - Teach tools (request_teach_access, teach_step, teach_batch) fall through
#     to the UPSTREAM chain. Sub-patches 2-5 ensure the upstream chain uses
#     __linuxExecutor and auto-grants permissions. The teach overlay (BrowserWindow
#     + IPC) works on Linux natively since it's pure Electron.
#   - request_access: handled directly on Linux — grants ALL requested apps at
#     full tier (no click-only/type restrictions). The upstream handler applies
#     macOS app tiers that restrict IDEs/terminals to "click" tier.
#   - Normal CU tools use a FAST DIRECT handler dispatching to __linuxExecutor,
#     skipping the macOS app tiers, allowlists, and permission dialogs.
#
# __DISPATCHER__ is replaced at patch time with the actual session dispatcher function
# name (e.g. EZr). __SELF__ is replaced with the object name (e.g. nnt).
with open(os.path.join(_CU_HERE, "../js/cu_handler_injection.js"), "r", encoding="utf-8") as _f:
    LINUX_HANDLER_INJECTION_JS = _f.read()


# kwin-wayland mode loads a separate Node module (js/executor_linux.js)
# that talks to kwin-portal-bridge. The source uses ES-module imports; we
# transform those to CommonJS require() calls and strip `export` keywords so
# the whole file can be injected as an IIFE into the bundled JS.
def build_kwin_linux_executor_injection():
    """Read executor_linux.js and transform it into an injectable IIFE for kwin-wayland mode."""

    here = os.path.dirname(__file__)
    source_path = os.path.join(here, "../js/executor_linux.js")
    with open(source_path, "r", encoding="utf-8") as f:
        js = f.read()

    replacements = [
        (
            "import { execFile as execFileCb, spawnSync } from 'node:child_process'\n",
            'var { execFile: execFileCb, spawnSync } = require("node:child_process");\n',
        ),
        (
            "import { execFile as execFileCb } from 'node:child_process'\n",
            'var { execFile: execFileCb } = require("node:child_process");\n',
        ),
        (
            "import { screen as electronScreen } from 'electron'\n",
            'var { screen: electronScreen } = require("electron");\n',
        ),
        (
            "import { promisify } from 'node:util'\n",
            'var { promisify } = require("node:util");\n',
        ),
    ]
    for old, new in replacements:
        js = js.replace(old, new)

    js = re.sub(r"^export\s+", "", js, flags=re.MULTILINE)
    js = (
        js.rstrip()
        + '\n\nglobalThis.__linuxExecutor = createLinuxExecutor({ hostBundleId: "com.anthropic.claude-desktop" });\n})();\n'
    )
    return "(function(){\n" + js


# Helpers used by the develop-mode bridge-controller patches (7b, 7c).
def find_string_marker(content, *messages):
    """Return the first matching marker index for any quoted or bare message."""

    for message in messages:
        encoded = message.encode("utf-8")
        for needle in (b'"' + encoded + b'"', b"'" + encoded + b"'", encoded):
            index = content.find(needle)
            if index != -1:
                return index
    return -1


def find_function_before_marker(content, marker_index):
    """Locate the nearest `function ... {` header before a marker."""

    function_index = content.rfind(b"function ", 0, marker_index)
    if function_index == -1:
        return None

    header_end = content.find(b"{", function_index, marker_index)
    if header_end == -1:
        return None

    return {
        "function_index": function_index,
        "header_end": header_end,
        "header": content[function_index : header_end + 1],
        "body": content[header_end + 1 : marker_index],
    }


# Runtime mode selection injected into the bundle — evaluated at Node startup.
# Sets globalThis.__cuKwinMode once; downstream text ternaries just read it.
#
# Precedence:
#   1. Explicit CLAUDE_CU_MODE env var wins (values: "regular" / "kwin-wayland",
#      anything else falls through to regular).
#   2. Auto-detect: XDG_SESSION_DESKTOP=KDE + XDG_SESSION_TYPE=wayland AND a
#      kwin-portal-bridge executable is reachable (either via
#      KWIN_PORTAL_BRIDGE_BIN or the first match on PATH) → kwin-wayland.
#   3. Fallback: regular (cross-distro).
#
# We walk PATH manually with fs.accessSync(X_OK) rather than shelling out to
# `which` so the check works on minimal distros and stays inside Node.
with open(os.path.join(_CU_HERE, "../js/cu_mode_preamble.js"), "rb") as _f:
    MODE_PREAMBLE_JS = _f.read()


def patch_computer_use_linux(filepath):
    """Make computer-use work on Linux by patching platform gates + providing Linux executor."""

    print("=== Patch: fix_computer_use_linux ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, "rb") as f:
        content = f.read()

    original_content = content
    changes = 0
    patches_applied = 0

    # Expected sub-patches (all must succeed — mode-gated branches still apply at
    # build time; runtime behavior is selected by CLAUDE_CU_MODE).
    #
    # Shared (apply in both modes):
    #   1  = Linux executor injection (both regular + kwin-wayland variants, runtime switch)
    #   2  = ese Set: add "linux"
    #   3  = createDarwinExecutor: Linux fallback
    #   4  = cu lock acquire: __setLockHeld(true) (no-op in regular via optional chaining)
    #   5  = cu lock release: __setLockHeld(false)
    #   6  = ensureOsPermissions: skip TCC on Linux
    #   7  = screenshot intro note workaround (linuxVisibleLastScreenshot)
    #   9  = teach overlay controller CU gate verify (no content change)
    #  10  = teach overlay bridge-backed init (capability-gated)
    #  11  = side-panel bridge-backed init (capability-gated)
    #  16  = teach overlay: VM-aware transparency
    #  17  = teach overlay display: force primary monitor
    #  18  = mVt isEnabled: force true on Linux
    #  19  = rj chicagoEnabled bypass: force true on Linux
    #
    # Regular mode (gated on !globalThis.__cuKwinMode):
    #   8  = handleToolCall hybrid dispatch
    #  12  = teach overlay mouse: tooltip-bounds polling
    #  13  = yJt setIgnoreMouseEvents neutralize
    #  14  = SUn setIgnoreMouseEvents neutralize
    #
    # kwin-wayland mode (gated on globalThis.__cuKwinMode):
    #  15  = glow overlay disable
    #  22  = plasmashell alias in request_access
    #  23  = plasmashell alias in request_teach_access
    #  24  = desktop shell hint template (plasmashell/Dolphin wording)
    #  25  = desktop shell grant predicate (plasmashell)
    #  26  = desktop shell detection (plasmashell)
    #  35  = CU env prompt: KDE/Dolphin/plasmashell suffix
    #
    # Text patches (3-way ternary: kwin-wayland/regular/other):
    #  20  = 13a Lf allowlist gate description (linux=empty)
    #  21  = 13b request_access macOS platform prefix → Linux/KDE/generic
    #  27  = 13c request_access apps: Linux identifiers (WM_CLASS)
    #  28  = 13d open_application app: Linux identifiers
    #  29  = 13e open_application desc: no allowlist on Linux
    #  30  = 13f screenshot desc: clean on Linux
    #  31  = 13g screenshot suffix: no allowlist error on Linux
    #  32  = 14a Separate filesystems → Same filesystem (2 occurrences, 3-way wording)
    #  33  = 14b Finder/Photos → generic Linux app terms
    #  34  = 14c File Explorer/Finder → Dolphin (kwin-wayland) / Files (regular)
    EXPECTED_PATCHES = 35

    # Patch 1: Inject Linux executor at app.on("ready") with runtime mode switch.
    # Both the regular (inline cross-distro) and kwin-wayland (external file,
    # kwin-portal-bridge) executors are embedded; one runs based on CLAUDE_CU_MODE.
    regular_js = LINUX_EXECUTOR_JS.strip().encode("utf-8")
    kwin_js = build_kwin_linux_executor_injection().strip().encode("utf-8")

    mode_preamble = MODE_PREAMBLE_JS

    ready_pattern = rb'(app\.on\("ready",async\(\)=>\{)'

    def inject_at_ready(m):
        return (
            m.group(1)
            + b'if(process.platform==="linux"){'
            + mode_preamble
            + b"if(globalThis.__cuKwinMode){"
            + kwin_js
            + b"}else{"
            + regular_js
            + b"}}"
        )

    content, count = re.subn(ready_pattern, inject_at_ready, content, count=1)
    if count >= 1:
        print(f"  [OK] Linux executor: injected regular + kwin-wayland variants ({count} match)")
        changes += count
        patches_applied += 1
    else:
        print('  [FAIL] app.on("ready") pattern: 0 matches')
        return False

    # Patch 2: Add "linux" to the computer-use platform Set
    # Original: new Set(["darwin","win32"])  (gates vee(), rj(), and other CU checks)
    # New: new Set(["darwin","win32","linux"])
    # This single change makes vee() return true on Linux, enabling the CU server push,
    # chicagoEnabled gate, overlay init, and all other ese.has() checks.
    set_pattern = rb'new Set\(\["darwin","win32"\]\)'
    set_replacement = b'new Set(["darwin","win32","linux"])'

    content, count = re.subn(set_pattern, set_replacement, content, count=1)
    if count >= 1:
        print(f"  [OK] ese Set: added linux ({count} match)")
        changes += count
        patches_applied += 1
    else:
        print("  [FAIL] ese Set pattern: 0 matches")
        return False

    # Patch 4: Patch createDarwinExecutor (L4r) to return Linux executor on Linux
    # Original: function L4r(t){if(process.platform!=="darwin")throw new Error(...)
    # New: function L4r(t){if(process.platform==="linux"&&globalThis.__linuxExecutor)return globalThis.__linuxExecutor;if(process.platform!=="darwin")throw...
    executor_pattern = rb'(function [\w$]+\([\w$]+\)\{)if\(process\.platform!=="darwin"\)throw new Error'

    def patch_executor(m):
        return m.group(1) + b'if(process.platform==="linux"&&globalThis.__linuxExecutor)return globalThis.__linuxExecutor;' + b'if(process.platform!=="darwin")throw new Error'

    content, count = re.subn(executor_pattern, patch_executor, content, count=1)
    if count >= 1:
        print(f"  [OK] createDarwinExecutor: Linux fallback ({count} match)")
        changes += count
        patches_applied += 1
    else:
        print("  [FAIL] createDarwinExecutor pattern: 0 matches")
        return False

    # Patch 4b (kwin-wayland): Tie bridge session lifecycle to the CU lock on Linux.
    # Upstream acquires/releases a global CU lock via xen.acquire/release. The
    # kwin-wayland executor exposes __setLockHeld(isHeld) to start/stop the
    # kwin-portal-bridge session. The regular executor does not expose __setLockHeld
    # — optional chaining (`.__setLockHeld?.(...)`) makes this a no-op in regular
    # mode. Safe to always apply.
    acquire_pattern = rb'this\.holder===void 0&&\(this\.holder=([\w$]+),this\.emit\("cuLockChanged",\{holder:\1\}\),([\w$]+)\(\)\)'

    def patch_lock_acquire(m):
        holder = m.group(1)
        callback = m.group(2)
        return (
            b"this.holder===void 0&&(this.holder="
            + holder
            + b',process.platform==="linux"&&globalThis.__linuxExecutor?.__setLockHeld?.(!0).catch?.(e=>console.warn("[linux-executor] failed to start bridge session on lock acquire",e)),this.emit("cuLockChanged",{holder:'
            + holder
            + b"}),"
            + callback
            + b"())"
        )

    content, count = re.subn(acquire_pattern, patch_lock_acquire, content, count=1)
    if count >= 1:
        print(f"  [OK] cu lock acquire: start bridge session on Linux ({count} match)")
        changes += count
        patches_applied += 1
    else:
        print("  [FAIL] cu lock acquire pattern: 0 matches")

    release_pattern = rb'this\.holder===([\w$]+)&&\(this\.holder=void 0,this\.emit\("cuLockChanged",\{holder:void 0\}\)\)'

    def patch_lock_release(m):
        holder = m.group(1)
        return (
            b"this.holder==="
            + holder
            + b'&&(this.holder=void 0,process.platform==="linux"&&globalThis.__linuxExecutor?.__setLockHeld?.(!1).catch?.(e=>console.warn("[linux-executor] failed to stop bridge session on lock release",e)),this.emit("cuLockChanged",{holder:void 0}))'
        )

    content, count = re.subn(release_pattern, patch_lock_release, content, count=1)
    if count >= 1:
        print(f"  [OK] cu lock release: stop bridge session on Linux ({count} match)")
        changes += count
        patches_applied += 1
    else:
        print("  [FAIL] cu lock release pattern: 0 matches")

    # Patch 5: Patch ensureOsPermissions to return granted:true on Linux
    # Original: ensureOsPermissions:JLr  (JLr calls claude-swift TCC checks)
    # New: on Linux, return {granted:true} — no TCC permissions needed
    perms_pattern = rb"ensureOsPermissions:([\w$]+)"

    def patch_perms(m):
        fn_name = m.group(1).decode("utf-8")
        return (f'ensureOsPermissions:process.platform==="linux"?async()=>({{granted:!0}}):{fn_name}').encode("utf-8")

    content, count = re.subn(perms_pattern, patch_perms, content, count=1)
    if count >= 1:
        print(f"  [OK] ensureOsPermissions: skip TCC on Linux ({count} match)")
        changes += count
        patches_applied += 1
    else:
        print("  [FAIL] ensureOsPermissions pattern: 0 matches")

    # Patch 5b (kwin-wayland): Show the monitor intro note again on the first
    # screenshot after a Linux wrapper is created from resumed session state.
    # Upstream caches lastScreenshot across the wrapper lifetime and hydrates it
    # from persisted screenshot dims, which suppresses the "screenshot taken on
    # monitor ..." note even before the first fresh screenshot. Keep the old data
    # available for coordinate-dependent tools but hide it from the *first*
    # screenshot call while there is no live screenshot yet. Harmless in regular
    # mode — the hybrid handler intercepts screenshot calls before this wrapper
    # path runs, so the closure binding is effectively dead code.
    if b"linuxVisibleLastScreenshot=" in content and (
        b"lastScreenshot:linuxVisibleLastScreenshot," in content
    ):
        print("  [OK] screenshot intro note workaround: already present")
        patches_applied += 1
    else:
        seed_pattern = (
            rb"async\(([\w$]+),[\w$]+\)=>\{"
            rb"[\s\S]{0,4000}?"
            rb";[\w$]+\(\)\}\}const ([\w$]+)=([\w$]+)"
            rb"\|\|\(([\w$]+)=([\w$]+)\.getLastScreenshotDims\)"
            rb"==null\?void 0:\4\.call\(\5\),"
            rb"([\w$]+)=new AbortController,([\w$]+)=\{"
        )
        seed_match = re.search(seed_pattern, content)
        if seed_match is None:
            print("  [FAIL] screenshot intro note: wrapper seed anchor not found")
        else:
            tool_name = seed_match.group(1)
            dims_var = seed_match.group(2)
            last_var = seed_match.group(3)
            injection = (
                b",linuxVisibleLastScreenshot="
                b'process.platform==="linux"&&'
                + last_var
                + b"===void 0&&"
                + tool_name
                + b'==="screenshot"?void 0:'
                + last_var
                + b"??("
                + dims_var
                + b'?{...'
                + dims_var
                + b',base64:""}:void 0)'
            )
            split = seed_match.start(6) - 1
            content = content[:split] + injection + content[split:]
            changes += 1

            last_screenshot_pattern = (
                rb"lastScreenshot:"
                + re.escape(last_var)
                + rb"\?\?\("
                + re.escape(dims_var)
                + rb"\?\{\.\.\."
                + re.escape(dims_var)
                + rb',base64:""\}:void 0\),'
            )
            content, ls_count = re.subn(
                last_screenshot_pattern,
                b"lastScreenshot:linuxVisibleLastScreenshot,",
                content,
                count=1,
            )
            if ls_count < 1:
                print("  [FAIL] screenshot intro note: lastScreenshot anchor not found")
            else:
                changes += 1
                patches_applied += 1
                print("  [OK] screenshot intro note: first wrapper screenshot restored")

    # Patch 6: Hybrid handleToolCall — inject early-return block at the top
    # The upstream handleToolCall calls a session-cached dispatcher. On Linux, we
    # inject an early-return block that:
    #   - For teach tools: falls through to the upstream chain (uses __linuxExecutor
    #     via sub-patch 4, auto-grants via sub-patch 5, teach overlay works natively)
    #   - For normal tools: fast direct dispatch to __linuxExecutor, skipping macOS
    #     app tiers, allowlists, CU lock, and permission dialogs
    #
    # Two-step approach:
    #   Step A: Find the handleToolCall start and capture object name + session param
    #   Step B: Find the dispatcher function name (const n=DISPATCHER(session_param))
    #   Then inject LINUX_HANDLER_INJECTION after the opening brace.

    # Step A: Match the handleToolCall start
    htc_start = rb"(([\w$]+)=\{isEnabled:[\w$]+=>[\w$]+\(\),handleToolCall:async\(([\w$]+),([\w$]+),([\w$]+)\)=>\{)"
    htc_match = re.search(htc_start, content)

    if htc_match:
        obj_name = htc_match.group(2).decode("utf-8")
        session_param = htc_match.group(5).decode("utf-8")
        inject_pos = htc_match.end()  # position right after the opening {

        # Step B: Find the dispatcher in the code after the opening brace
        # It appears as: const n=DISPATCHER(SESSION_PARAM),{save_to_disk:
        after_brace = content[inject_pos : inject_pos + 2000]
        dispatcher_match = re.search(
            rb"const [\w$]+=([\w$]+)\(" + session_param.encode("utf-8") + rb"\),\{save_to_disk:",
            after_brace,
        )

        if dispatcher_match:
            dispatcher = dispatcher_match.group(1).decode("utf-8")
            handler_js = LINUX_HANDLER_INJECTION_JS.strip()
            handler_js = handler_js.replace("__SELF__", obj_name)
            handler_js = handler_js.replace("__DISPATCHER__", dispatcher)
            # Gate the hybrid dispatcher on regular mode. In kwin-wayland mode,
            # handleToolCall stays on the upstream path so the MCP layer can
            # exercise the bridge-backed executor directly.
            handler_js = handler_js.replace(
                'if(process.platform==="linux"){',
                'if(process.platform==="linux"&&!globalThis.__cuKwinMode){',
                1,
            )
            content = content[:inject_pos] + handler_js.encode("utf-8") + content[inject_pos:]
            print("  [OK] handleToolCall: regular-mode hybrid dispatch (gated; kwin-wayland falls through to upstream)")
            changes += 1
            patches_applied += 1
        else:
            print("  [FAIL] handleToolCall dispatcher not found")
            return False
    else:
        print("  [FAIL] handleToolCall pattern: 0 matches")
        return False

    # Patch 7: Teach overlay controller init on Linux
    # In v1.2.234+, the overlay init is gated by vee() which we patched via the Set fix.
    # The code `vee()&&(Sti(t),...)` will now run on Linux automatically.
    # No explicit injection needed — just verify the pattern exists.
    stub_end = rb"listInstalledApps:\(\)=>\[\]\}\)"
    stub_match = re.search(stub_end, content)
    if stub_match:
        # Check that the Set-based CU gate follows the stub (meaning overlay init is gated)
        # The gate function name changes every release (vee→MX→...) but always calls
        # <name>.has(process.platform) on the ese/gie Set we already patched.
        after_stub = content[stub_match.end() : stub_match.end() + 50]
        # The gate function name is minified and changes every release (vee→MX→nee→...).
        # Match any short function call followed by &&( which is the standard gate pattern.
        if b".has(process.platform)" in after_stub or re.search(rb",[\w$]+\(\)&&\(", after_stub):
            print("  [OK] teach overlay controller: CU gate found (handled by Set fix)")
            patches_applied += 1
        else:
            print("  [FAIL] teach overlay: CU gate not found after TCC stub — may need manual check")
    else:
        print("  [FAIL] teach overlay: TCC stub pattern not found")

    # Patch 7b (kwin-wayland): Route teach-overlay controller init through the
    # bridge when the kwin-wayland executor is active. Capability-gated: only fires
    # when globalThis.__linuxExecutor exposes __initTeachController, which the
    # regular inline executor does not — so this returns early in kwin-wayland mode
    # and falls through to upstream BrowserWindow + patches 8-10 in regular mode.
    if b"globalThis.__linuxExecutor?.__initTeachController" in content:
        print("  [OK] teach overlay controller: bridge-backed init already present")
        patches_applied += 1
    else:
        marker_index = find_string_marker(content, "[cu-teach] controller initialized")
        if marker_index == -1:
            print("  [FAIL] teach overlay controller marker: not found")
        else:
            function_info = find_function_before_marker(content, marker_index)
            if function_info is None:
                print("  [FAIL] teach overlay controller init header: not found")
            else:
                header_match = re.fullmatch(
                    rb"function [\w$]+\(([\w$]+),([\w$]+)\)\{",
                    function_info["header"],
                )
                if (
                    not header_match
                    or b'.on("teachModeChanged"' not in function_info["body"]
                    or b'.on("teachStepRequested"' not in function_info["body"]
                ):
                    print("  [FAIL] teach overlay controller init function shape: unexpected")
                else:
                    manager = header_match.group(1).decode("utf-8")
                    main_window = header_match.group(2).decode("utf-8")
                    injected = (
                        f'if(process.platform==="linux"&&globalThis.__linuxExecutor?.__initTeachController){{globalThis.__linuxExecutor.__initTeachController({manager},{main_window});return;}}'
                    ).encode("utf-8")
                    content = (
                        content[: function_info["header_end"] + 1]
                        + injected
                        + content[function_info["header_end"] + 1 :]
                    )
                    print("  [OK] teach overlay controller: Linux bridge-backed init")
                    changes += 1
                    patches_applied += 1

    # Patch 7c (kwin-wayland): Route the CU side-panel controller init through
    # the bridge's __initDockController when available (kwin-wayland mode). Falls
    # back to upstream Electron BrowserWindow#setBounds when the executor doesn't
    # expose this method (regular mode).
    if b"globalThis.__linuxExecutor?.__initDockController" in content:
        print("  [OK] cu side-panel: bridge-backed init already present")
        patches_applied += 1
    else:
        marker_index = find_string_marker(content, "[cu-side-panel] initialized")
        if marker_index == -1:
            print("  [FAIL] cu side-panel controller marker: not found")
        else:
            function_info = find_function_before_marker(content, marker_index)
            if function_info is None:
                print("  [FAIL] cu side-panel controller init header: not found")
            else:
                header_match = re.fullmatch(
                    rb"function [\w$]+\(([\w$]+)\)\{", function_info["header"]
                )
                if (
                    not header_match
                    or b'.on("cuLockChanged"' not in function_info["body"]
                ):
                    print("  [FAIL] cu side-panel controller init function shape: unexpected")
                else:
                    main_window = header_match.group(1).decode("utf-8")
                    injected = (
                        f'if(process.platform==="linux"&&globalThis.__linuxExecutor?.__initDockController){{globalThis.__linuxExecutor.__initDockController({main_window});return;}}'
                    ).encode("utf-8")
                    content = (
                        content[: function_info["header_end"] + 1]
                        + injected
                        + content[function_info["header_end"] + 1 :]
                    )
                    print("  [OK] cu side-panel: Linux bridge-backed init")
                    changes += 1
                    patches_applied += 1

    # Patch 8: Fix teach overlay mouse events on Linux
    # On macOS, setIgnoreMouseEvents(true, {forward: true}) makes transparent areas
    # click-through while still receiving mouseenter/mouseleave events. On Linux/X11,
    # {forward: true} is NOT implemented (Electron issue #16777, open since 2019).
    # The overlay becomes fully click-through and NEVER receives mouseenter, so the
    # tooltip buttons (Next/Exit) remain unclickable forever.
    #
    # Fix: Override setIgnoreMouseEvents to a no-op on the teach overlay window.
    # This keeps the overlay permanently interactive so tooltip buttons work.
    # Trade-off: users can't click through to apps behind the overlay during
    # the teach session — acceptable for a guided tour. The no-op also prevents
    # the upstream mouse-leave IPC handler and step transition functions (yJt/SUn)
    # from setting the window back to pass-through.

    # Find the overlay variable name from: OVERLAYVAR.setAlwaysOnTop(!0,"screen-saver"),OVERLAYVAR.setFullScreenable(!1),OVERLAYVAR.setIgnoreMouseEvents(!0,{forward:!0})
    overlay_var_pattern = rb'([\w$]+)\.setAlwaysOnTop\(!0,"screen-saver"\),\1\.setFullScreenable\(!1\),\1\.setIgnoreMouseEvents\(!0,\{forward:!0\}\)'

    overlay_var_match = re.search(overlay_var_pattern, content)
    if overlay_var_match:
        ov = overlay_var_match.group(1).decode("utf-8")  # e.g. oa

        # Replace the initial setIgnoreMouseEvents on the overlay with Linux tooltip-bounds polling
        old_init = f"{ov}.setIgnoreMouseEvents(!0,{{forward:!0}})".encode("utf-8")

        new_init = (
            '(process.platform==="linux"?'
            # On Linux, override setIgnoreMouseEvents to a no-op so the teach overlay
            # stays interactive throughout its lifetime. Electron bug #16777 means
            # {forward:true} doesn't work on Linux/X11 — the overlay would become
            # permanently pass-through with no way back. By keeping it interactive,
            # users can click Next/Exit buttons. The trade-off: users can't click
            # through to apps behind the overlay during teach — acceptable for a
            # guided tour. The upstream mouse-leave IPC handler and yJt/SUn step
            # transitions all call setIgnoreMouseEvents on this window — the no-op
            # prevents them from breaking interactivity.
            f"({ov}.setIgnoreMouseEvents=function(){{}},"  # no-op override
            f"globalThis.__isVM&&{ov}.setOpacity(.15))"
            f":{ov}.setIgnoreMouseEvents(!0,{{forward:!0}}))"
        ).encode("utf-8")

        # Only replace the first occurrence (overlay init)
        content = content.replace(old_init, new_init, 1)
        if new_init in content:
            print(f"  [OK] teach overlay mouse: tooltip-bounds polling for Linux ({ov})")
            changes += 1
            patches_applied += 1
        else:
            print("  [FAIL] teach overlay mouse: replacement failed")
    else:
        print("  [FAIL] teach overlay mouse: overlay variable pattern not found")

    # Patch 9: Neutralize setIgnoreMouseEvents resets in yJt/SUn on Linux
    # The upstream code calls setIgnoreMouseEvents(true,{forward:true}) in two places
    # during step transitions: yJt() (show step) and SUn() (working state).
    # Patch 8's no-op override already catches these on the teach overlay window.
    # This patch is a belt-and-suspenders safety net for cases where the function
    # parameter differs from the global overlay variable (yJt receives it as a param).
    #
    # Pattern in yJt: OVERLAYVAR.setIgnoreMouseEvents(!0,{forward:!0}),OVERLAYVAR.webContents.send("cu-teach:show"
    # Pattern in SUn: OVERLAYVAR.setIgnoreMouseEvents(!0,{forward:!0}),OVERLAYVAR.webContents.send("cu-teach:working"

    if overlay_var_match:
        # 9a: yJt() uses function parameter (not global oa) — pattern: function yJt(PARAM,e){PARAM.setIgnoreMouseEvents(!0,{forward:!0})
        yjt_pat = rb"(function [\w$]+\([\w$]+,[\w$]+\)\{)([\w$]+)(\.setIgnoreMouseEvents\(!0,\{forward:!0\}\))"

        def yjt_repl(m):
            fn_head = m.group(1).decode("utf-8")
            var = m.group(2).decode("utf-8")
            rest = m.group(3).decode("utf-8")
            return f'{fn_head}(process.platform!=="linux"&&{var}{rest})'.encode("utf-8")

        content_new, yjt_count = re.subn(yjt_pat, yjt_repl, content, count=1)
        if yjt_count:
            content = content_new
            print("  [OK] teach overlay: neutralized setIgnoreMouseEvents in show handler (yJt) for Linux")
            changes += 1
            patches_applied += 1
        else:
            print("  [FAIL] teach overlay: yJt pattern not found")

        # 9b: SUn() uses global overlay var — pattern: oa.setIgnoreMouseEvents(!0,{forward:!0}),oa.webContents.send("cu-teach:working"
        sun_pat = f'{ov}.setIgnoreMouseEvents(!0,{{forward:!0}}),{ov}.webContents.send("cu-teach:working"'.encode("utf-8")
        sun_repl = f'(process.platform!=="linux"&&{ov}.setIgnoreMouseEvents(!0,{{forward:!0}})),{ov}.webContents.send("cu-teach:working"'.encode("utf-8")
        if sun_pat in content:
            content = content.replace(sun_pat, sun_repl, 1)
            print("  [OK] teach overlay: neutralized setIgnoreMouseEvents in working handler (SUn) for Linux")
            changes += 1
            patches_applied += 1
        else:
            print("  [FAIL] teach overlay: SUn pattern not found")

    # Patch 8a (kwin-wayland): Disable the CU glow overlay in kwin-wayland mode only.
    # The glow overlay is a separate BrowserWindow that follows the CU lock holder;
    # in kwin-wayland mode the bridge provides its own visual feedback. In regular
    # mode the overlay stays enabled. Pattern: function Eei(t,e){su.on("cuLockChanged",...
    glow_init_pattern = (
        rb'(function [\w$]+\(([\w$]+),([\w$]+)\)\{)([\w$]+)\.on\("cuLockChanged",'
    )

    def patch_glow_init(m):
        return (
            m.group(1)
            + b'if(process.platform==="linux"&&globalThis.__cuKwinMode)return;'
            + m.group(4)
            + b'.on("cuLockChanged",'
        )

    content, count = re.subn(glow_init_pattern, patch_glow_init, content, count=1)
    if count >= 1:
        print(f"  [OK] cu glow overlay: disabled in kwin-wayland mode ({count} match)")
        changes += count
        patches_applied += 1
    else:
        print("  [FAIL] cu glow overlay pattern: 0 matches")

    # Patch 10: Fix teach overlay transparency on VMs
    # The fullscreen transparent BrowserWindow causes GPU crashes and cursor artifacts
    # on virtual GPUs (VirtualBox VMSVGA, etc.). On native hardware it works fine.
    # Detect VMs at runtime using systemd-detect-virt and fall back to a dark backdrop.
    # Native hardware keeps full transparency (see-through overlay like macOS).
    teach_overlay_pattern = rb'(=new [\w$]+\.BrowserWindow\(\{[^}]*?)transparent:!0([^}]*?)backgroundColor:"#00000000"'
    teach_overlay_matches = list(re.finditer(teach_overlay_pattern, content))
    for m in teach_overlay_matches:
        before = content[max(0, m.start() - 80) : m.start()]
        if b"workArea" in before:
            old = m.group(0)
            new = old.replace(b"transparent:!0", b"transparent:!globalThis.__isVM").replace(b'backgroundColor:"#00000000"', b'backgroundColor:globalThis.__isVM?"#000000":"#00000000"')
            content = content.replace(old, new, 1)
            print("  [OK] teach overlay: VM-aware transparency (transparent on native, dark backdrop on VMs)")
            changes += 1
            patches_applied += 1
            break
    else:
        print("  [FAIL] teach overlay transparency pattern not found")

    # Patch 10b: Force teach overlay display to primary monitor on Linux
    # The xlr() function resolves which display to use for the glow and teach overlay
    # windows. On macOS, autoTargetDisplay + findWindowDisplays determines the correct
    # display. On Linux, these fall back to the Claude Desktop window's display, which
    # may be a non-primary monitor. We simplify: on Linux, always use the primary
    # monitor for teach overlays. This avoids fragile xdotool-based window detection
    # that only works on X11 and keeps the teach experience consistent across distros.
    # Pattern: function xlr(PARAM){return PARAM===null?ELECTRON.screen.getPrimaryDisplay():...}
    xlr_pattern = rb"(function [\w$]+\(([\w$]+)\)\{)(return \2===null\?[\w$]+\.screen\.getPrimaryDisplay\(\):[\w$]+\.screen\.getAllDisplays\(\)\.find)"

    def patch_xlr(m):
        param = m.group(2).decode("utf-8")
        return m.group(1) + f'if(process.platform==="linux"){param}=null;'.encode("utf-8") + m.group(3)

    content, count = re.subn(xlr_pattern, patch_xlr, content, count=1)
    if count >= 1:
        print(f"  [OK] teach overlay display: forced to primary monitor on Linux ({count} match)")
        changes += count
        patches_applied += 1
    else:
        print("  [FAIL] xlr display resolver pattern: 0 matches (teach may appear on wrong monitor)")

    # Patch 11: Force mVt() (computer-use isEnabled gate) to return true on Linux
    # The mVt() function gates whether the computer-use MCP server is enabled for
    # ALL session types (CCD, cowork, dispatch). It checks:
    #   fn(serverFlag) ? ese.has(platform) && Rse() : rj()
    # Both branches call Rse(), which reads the "enabled" key from GrowthBook's
    # chicago_config. Anthropic's server returns enabled:false, so mVt() returns
    # false even though our other patches (Set fix, executor, permissions) are working.
    # Our enable_local_agent_mode.py only overrides {status:"supported"} in the
    # static registry — it doesn't affect the GrowthBook "enabled" key.
    # Fix: inject an early return true on Linux before the original logic.
    mVt_pattern = rb"(function [\w$]+\(\)\{)return [\w$]+\([\w$]+\)\?[\w$]+\.has\(process\.platform\)&&[\w$]+\(\):[\w$]+\(\)\}"

    def patch_mVt(m):
        return m.group(1) + b'if(process.platform==="linux")return!0;' + m.group(0)[len(m.group(1)) :]

    content, count = re.subn(mVt_pattern, patch_mVt, content, count=1)
    if count >= 1:
        print(f"  [OK] mVt isEnabled: force true on Linux ({count} match)")
        changes += count
        patches_applied += 1
    else:
        print("  [FAIL] mVt isEnabled pattern: 0 matches (computer-use may not work in cowork/CCD)")

    # Patch 12: Force rj() to return true on Linux (bypass chicagoEnabled + GrowthBook)
    # rj() is the single function that feeds BOTH runtime gates:
    #   - isDisabled() = !rj()  → blocks tool calls when false
    #   - hasComputerUse = rj() → controls system prompt CU instructions
    # Original: rj() = ese.has(platform) ? Rse() && Rr("chicagoEnabled") : false
    # Rse() reads GrowthBook enabled:false, Rr reads chicagoEnabled preference (default false).
    # Both fail → rj()=false → tools blocked. The Settings toggle (claude.ai web UI)
    # is server-rendered and hidden on Linux regardless of our main-process patches.
    # Fix: return true unconditionally on Linux — no config entry needed.
    rj_pattern = rb'(function [\w$]+\(\)\{)return [\w$]+\.has\(process\.platform\)\?[\w$]+\(\)&&[\w$]+\("chicagoEnabled"\):!1\}'

    def patch_rj(m):
        return m.group(1) + b'if(process.platform==="linux")return!0;' + m.group(0)[len(m.group(1)) :]

    content, count = re.subn(rj_pattern, patch_rj, content, count=1)
    if count >= 1:
        print(f"  [OK] rj chicagoEnabled bypass: force true on Linux ({count} match)")
        changes += count
        patches_applied += 1
    else:
        print("  [FAIL] rj pattern: 0 matches (computer-use tool calls may be blocked)")

    # ─── Patch 13: Linux-aware computer-use tool descriptions ───────────────
    # V7r() builds CU tool definitions with descriptions that assume macOS or
    # Windows. On Linux, the model sees wrong platform info ("macOS", "Finder"),
    # irrelevant allowlist/permission warnings (bypassed by sub-patches 5-6),
    # and macOS-specific bundle identifiers. Fix: wrap key description strings
    # in platform checks. Non-fatal — tools work regardless of descriptions.

    print("  --- Tool description patches (non-fatal) ---")
    desc_changes = 0

    # 13a: Lf (allowlist gate warning) — empty on Linux
    # Lf is appended to 14+ tool descriptions via ${Lf} template literals.
    # On Linux the allowlist is bypassed (sub-patch 6), so the warning is wrong.
    lf_pat = rb'([\w$]+)="The frontmost application must be in the session allowlist at the time of this call, or this tool returns an error and does nothing\."'

    def lf_repl(m):
        v = m.group(1).decode("utf-8")
        return (f'{v}=process.platform==="linux"?"":"The frontmost application must be in the session allowlist at the time of this call, or this tool returns an error and does nothing."').encode(
            "utf-8"
        )

    content, count = re.subn(lf_pat, lf_repl, content, count=1)
    if count:
        print("  [OK] 13a Lf allowlist gate: empty on Linux")
        desc_changes += 1
        patches_applied += 1
    else:
        print("  [FAIL] 13a Lf: not found")

    # 13b: request_access — "Linux" instead of "macOS"/"Finder"
    # 3-way ternary: kwin-wayland mode gets KDE-specific wording (Dolphin/Plasma),
    # regular mode gets generic Linux wording, non-Linux keeps upstream macOS text.
    _old_13b = b"""'This computer is running macOS. The file manager is "Finder". '"""
    _new_13b = (
        b"""(process.platform==="linux"?(globalThis.__cuKwinMode?"""
        b"""'This computer is running Linux with KDE Plasma. The file manager is \\"Dolphin\\". '"""
        b""":"""
        b"""'This computer is running Linux. """
        b"""On Linux, ALL applications are automatically accessible at full """
        b"""tier without explicit permission grants. You do NOT need to call """
        b"""request_access before using other tools. If called, it returns """
        b"""synthetic grant confirmations. The file manager depends on the """
        b"""desktop environment (e.g. Nautilus on GNOME, Dolphin on KDE, """
        b"""Thunar on XFCE). ')"""
        b""":"""
        b"""'This computer is running macOS. The file manager is "Finder". ')"""
    )
    if _old_13b in content:
        content = content.replace(_old_13b, _new_13b, 1)
        print("  [OK] 13b request_access: 3-way (kwin-wayland=KDE/Dolphin, regular=generic Linux, other=macOS)")
        desc_changes += 1
        patches_applied += 1
    else:
        print("  [FAIL] 13b request_access macOS prefix: not found")

    # 13b.kwin-alias (kwin-wayland): Map org.kde.plasmashell -> plasmashell in
    # request_access. The bridge-backed access layer keys off plasmashell, but
    # upstream schemas still accept the reverse-DNS form. Mode-gated at JS-runtime
    # so regular mode keeps the original array untouched.
    request_access_alias_pattern = (
        rb'(const ([\w$]+)=[\w$]+\.apps;if\(!Array\.isArray\(\2\)\|\|!\2\.every\(([\w$]+)=>typeof \3=="string"\)\)return [\w$]+\(\'"apps" must be an array of strings\.\',"bad_args"\);const )'
        rb"([\w$]+)=\2(,[\w$]+=\{\};)"
    )

    def patch_request_access_alias(m):
        return (
            m.group(1)
            + m.group(4)
            + b"=globalThis.__cuKwinMode?"
            + m.group(2)
            + b'.map(v=>v==="org.kde.plasmashell"?"plasmashell":v):'
            + m.group(2)
            + m.group(5)
        )

    content, count = re.subn(
        request_access_alias_pattern,
        patch_request_access_alias,
        content,
        count=1,
    )
    if count >= 1:
        print("  [OK] 13b.kwin-alias request_access: org.kde.plasmashell -> plasmashell (kwin-wayland mode)")
        desc_changes += 1
        patches_applied += 1
    else:
        print("  [FAIL] 13b.kwin-alias request_access alias: not found")

    # 13b.kwin-alias-teach (kwin-wayland): Same plasmashell alias for request_teach_access.
    teach_access_alias_pattern = (
        rb'(const ([\w$]+)=[\w$]+\.apps;if\(!Array\.isArray\(\2\)\|\|!\2\.every\(([\w$]+)=>typeof \3=="string"\)\)return [\w$]+\(\'"apps" must be an array of strings\.\',"bad_args"\);const )'
        rb"([\w$]+)=\2(,\{needDialog:)"
    )

    def patch_teach_access_alias(m):
        return (
            m.group(1)
            + m.group(4)
            + b"=globalThis.__cuKwinMode?"
            + m.group(2)
            + b'.map(v=>v==="org.kde.plasmashell"?"plasmashell":v):'
            + m.group(2)
            + m.group(5)
        )

    content, count = re.subn(
        teach_access_alias_pattern,
        patch_teach_access_alias,
        content,
        count=1,
    )
    if count >= 1:
        print("  [OK] 13b.kwin-alias-teach request_teach_access: plasmashell alias (kwin-wayland mode)")
        desc_changes += 1
        patches_applied += 1
    else:
        print("  [FAIL] 13b.kwin-alias-teach request_teach_access alias: not found")

    # 13b.kwin-shell-hint (kwin-wayland): Rewrite the "desktop shell is frontmost"
    # prompt to point at plasmashell + Dolphin instead of File Explorer/Finder.
    # kwin-wayland only.
    desktop_shell_prefix = (
        b"`The desktop shell is frontmost. Double-click, right-click, and Enter on "
        b"desktop items can launch applications outside the allowlist. To interact "
        b"with the desktop, taskbar, Start menu, Search, or file manager, call "
        b'request_access with exactly "${'
    )
    desktop_shell_suffix = (
        b'==="win32"?"File Explorer":"Finder"}" in the apps array \xe2\x80\x94 '
        b"that single grant covers all of them. To interact with a different app, "
        b"use open_application to bring it forward.`"
    )
    desktop_shell_pattern = (
        re.escape(desktop_shell_prefix) + rb"([\w$]+)" + re.escape(desktop_shell_suffix)
    )
    shell_match = re.search(desktop_shell_pattern, content)
    if shell_match:
        plat_var = shell_match.group(1).decode("utf-8")
        new_desktop_shell = (
            b"`${globalThis.__cuKwinMode?`The desktop shell is frontmost. Desktop icons, panels, launchers, and "
            b'widgets belong to Plasma Shell. To interact with them, call request_access with exactly \\"plasmashell\\" in '
            b'the apps array. If you need the file manager, request \\"Dolphin\\" separately. To interact with a '
            b"different app, use open_application to bring it forward.`:`The desktop shell is frontmost. Double-click, "
            b"right-click, and Enter on desktop items can launch applications outside the allowlist. To interact "
            b"with the desktop, taskbar, Start menu, Search, or file manager, call request_access with exactly "
            b'\\"${'
            + plat_var.encode("utf-8")
            + b'==="win32"?"File Explorer":"Finder"}\\" in the apps array \xe2\x80\x94 that single grant covers all '
            b"of them. To interact with a different app, use open_application to bring it forward.`}`"
        )
        content = content.replace(shell_match.group(0), new_desktop_shell, 1)
        print("  [OK] 13b.kwin-shell-hint: kwin-wayland=plasmashell, regular/other=upstream wording")
        desc_changes += 1
        patches_applied += 1
    else:
        print("  [FAIL] 13b.kwin-shell-hint desktop shell hint: not found")

    # 13b.kwin-shell-grant (kwin-wayland): Teach the grant predicate that plasmashell
    # bundle IDs satisfy desktop-shell access. Regular mode keeps upstream's
    # darwin/win32 predicate untouched; kwin-wayland short-circuits on the
    # plasmashell IDs.
    shell_grant_pattern = (
        rb"(function [\w$]+\(([\w$]+),([\w$]+)\)\{)"
        rb'return \3==="darwin"\?\2\.some\(([\w$]+)=>\4\.bundleId===([\w$]+)\):'
        rb"\2\.some\(([\w$]+)=>\6\.bundleId\.toLowerCase\(\)===([\w$]+)\)\}"
    )

    def patch_shell_grant(m):
        header, apps, plat, darwin_iter, mac_const, win_iter, win_const = (
            m.group(1),
            m.group(2),
            m.group(3),
            m.group(4),
            m.group(5),
            m.group(6),
            m.group(7),
        )
        return (
            header
            + b"return "
            + plat
            + b'==="darwin"?'
            + apps
            + b".some("
            + darwin_iter
            + b"=>"
            + darwin_iter
            + b".bundleId==="
            + mac_const
            + b"):globalThis.__cuKwinMode&&"
            + plat
            + b'==="linux"?'
            + apps
            + b".some("
            + darwin_iter
            + b"=>"
            + darwin_iter
            + b'.bundleId==="plasmashell"||'
            + darwin_iter
            + b'.bundleId==="org.kde.plasmashell"):'
            + apps
            + b".some("
            + win_iter
            + b"=>"
            + win_iter
            + b".bundleId.toLowerCase()==="
            + win_const
            + b")}"
        )

    content, count = re.subn(shell_grant_pattern, patch_shell_grant, content, count=1)
    if count >= 1:
        print("  [OK] 13b.kwin-shell-grant: plasmashell satisfies shell access (kwin-wayland only)")
        desc_changes += 1
        patches_applied += 1
    else:
        print("  [FAIL] 13b.kwin-shell-grant desktop shell grant predicate: not found")

    # 13b.kwin-shell-detect (kwin-wayland): Short-circuit the shell-process detector
    # on plasmashell IDs. Same mode gate.
    shell_detect_pattern = (
        rb"(function [\w$]+\(([\w$]+)\)\{)"
        rb"return \2===([\w$]+)\?!0:!([\w$]+)\|\|!([\w$]+)\.has\(([\w$]+)\(\2\)\)"
        rb"\?!1:\2\.toLowerCase\(\)\.startsWith\(\4\)\}"
    )

    def patch_shell_detect(m):
        header, arg, mac_const, win_prefix, win_set, win_norm = (
            m.group(1),
            m.group(2),
            m.group(3),
            m.group(4),
            m.group(5),
            m.group(6),
        )
        return (
            header
            + b"return "
            + arg
            + b"==="
            + mac_const
            + b"||globalThis.__cuKwinMode&&("
            + arg
            + b'==="plasmashell"||'
            + arg
            + b'==="org.kde.plasmashell")?!0:!'
            + win_prefix
            + b"||!"
            + win_set
            + b".has("
            + win_norm
            + b"("
            + arg
            + b"))?!1:"
            + arg
            + b".toLowerCase().startsWith("
            + win_prefix
            + b")}"
        )

    content, count = re.subn(shell_detect_pattern, patch_shell_detect, content, count=1)
    if count >= 1:
        print("  [OK] 13b.kwin-shell-detect: plasmashell recognized as shell (kwin-wayland only)")
        desc_changes += 1
        patches_applied += 1
    else:
        print("  [FAIL] 13b.kwin-shell-detect desktop shell detection: not found")

    # 13c: App identifier (request_access apps schema) — WM_CLASS for Linux
    # macOS uses bundle identifiers (com.tinyspeck.slackmacgap) — N/A on Linux.
    _old_13c = (
        b"""'Application display names (e.g. "Slack", "Calendar") or bundle identifiers (e.g. "com.tinyspeck.slackmacgap"). Display names are resolved case-insensitively against installed apps.'"""
    )
    _new_13c = (
        b"""(process.platform==="linux"?"""
        b"""'Application names as shown in window titles, or WM_CLASS values """
        b"""(e.g. "firefox", "org.gnome.Nautilus"). """
        b"""On Linux all apps are auto-granted at full tier.'"""
        b""":"""
        b"""'Application display names (e.g. "Slack", "Calendar") or bundle """
        b"""identifiers (e.g. "com.tinyspeck.slackmacgap"). Display names are """
        b"""resolved case-insensitively against installed apps.')"""
    )
    if _old_13c in content:
        content = content.replace(_old_13c, _new_13c, 1)
        print("  [OK] 13c request_access apps: Linux identifiers")
        desc_changes += 1
        patches_applied += 1
    else:
        print("  [FAIL] 13c request_access apps: not found")

    # 13d: App identifier (open_application app schema) — simplified for Linux
    _old_13d = b"""'Display name (e.g. "Slack") or bundle identifier (e.g. "com.tinyspeck.slackmacgap").'"""
    _new_13d = (
        b"""(process.platform==="linux"?"""
        b"""'Application name or WM_CLASS (e.g. "firefox", "nautilus").'"""
        b""":"""
        b"""'Display name (e.g. "Slack") or bundle identifier (e.g. "com.tinyspeck.slackmacgap").')"""
    )
    if _old_13d in content:
        content = content.replace(_old_13d, _new_13d, 1)
        print("  [OK] 13d open_application app: Linux identifiers")
        desc_changes += 1
        patches_applied += 1
    else:
        print("  [FAIL] 13d open_application app: not found")

    # 13e: open_application — no allowlist on Linux
    _old_13e = ('"Bring an application to the front, launching it if necessary. The target application must already be in the session allowlist \u2014 call request_access first."').encode("utf-8")
    _new_13e = (
        '(process.platform==="linux"?'
        '"Bring an application to the front, launching it if necessary. '
        'On Linux, all applications are directly accessible."'
        ":"
        '"Bring an application to the front, launching it if necessary. '
        "The target application must already be in the session allowlist "
        '\u2014 call request_access first.")'
    ).encode("utf-8")
    if _old_13e in content:
        content = content.replace(_old_13e, _new_13e, 1)
        print("  [OK] 13e open_application: no allowlist on Linux")
        desc_changes += 1
        patches_applied += 1
    else:
        print("  [FAIL] 13e open_application: not found")

    # 13f: screenshot (none-filtering) — remove allowlist text on Linux
    _old_13f = (
        '"Take a screenshot of the primary display. On this platform, '
        "screenshots are NOT filtered \u2014 all open windows are visible. "
        'Input actions targeting apps not in the session allowlist are rejected."'
    ).encode("utf-8")
    _new_13f = (
        '(process.platform==="linux"?'
        '"Take a screenshot of the primary display. '
        'All open windows are visible."'
        ":"
        '"Take a screenshot of the primary display. On this platform, '
        "screenshots are NOT filtered \u2014 all open windows are visible. "
        'Input actions targeting apps not in the session allowlist are rejected.")'
    ).encode("utf-8")
    if _old_13f in content:
        content = content.replace(_old_13f, _new_13f, 1)
        print("  [OK] 13f screenshot: clean description on Linux")
        desc_changes += 1
        patches_applied += 1
    else:
        print("  [FAIL] 13f screenshot: not found")

    # 13g: screenshot suffix — remove "allowlist empty" error on Linux
    ss_sfx_pat = rb'([\w$]+)\+" Returns an error if the allowlist is empty\. The returned image is what subsequent click coordinates are relative to\."'

    def ss_sfx_repl(m):
        v = m.group(1).decode("utf-8")
        return (
            f'{v}+(process.platform==="linux"'
            f'?" The returned image is what subsequent click coordinates are relative to."'
            f':" Returns an error if the allowlist is empty. The returned image is what subsequent click coordinates are relative to.")'
        ).encode("utf-8")

    content, count = re.subn(ss_sfx_pat, ss_sfx_repl, content, count=1)
    if count:
        print("  [OK] 13g screenshot suffix: no allowlist error on Linux")
        desc_changes += 1
        patches_applied += 1
    else:
        print("  [FAIL] 13g screenshot suffix: not found")

    if desc_changes > 0:
        changes += desc_changes
        print(f"  [OK] {desc_changes}/12 description patches applied (7 regular + 5 kwin-wayland KDE)")
    else:
        print("  [FAIL] No description patches applied (descriptions unchanged)")

    # ── Sub-patch 14: Linux-aware CU system prompt ──────────────────────────
    #
    # The CU system prompt (injected into CCD and cuOnlyMode sessions) contains
    # macOS-centric text that misleads the model on Linux:
    #
    # 14a: "Separate filesystems" paragraph says the CLI runs in a sandbox
    #       separate from the user's machine. On Linux native (hostLoopMode),
    #       there is no sandbox — CLI and desktop run on the same machine.
    #       This appears in both Bfn() (cuOnlyMode) and the normal CCD if(h) block.
    #
    # 14b: "Finder, Photos, System Settings" — macOS app names in the tool
    #       tier list. On Linux, use generic terms that work across all distros
    #       (Arch, Ubuntu, Fedora, NixOS, etc.): "the file manager, image viewer,
    #       system settings". Specific app names vary by DE (Nautilus/Dolphin/
    #       Thunar, Eye of GNOME/Gwenview, GNOME Settings/KDE System Settings).
    #
    # 14c: "File Explorer":"Finder" — platform-conditional file manager name
    #       in the host filesystem section. Needs Linux branch.

    # 14a: Replace "Separate filesystems" paragraph (2 occurrences: Bfn + CCD)
    _sep_old = b"**Separate filesystems.**"
    _sep_new = (
        b'**(process.platform==="linux"'
        b'?"**Same filesystem.** Computer-use actions and your CLI tools operate on the same Linux machine. '
        b"There is no sandbox \\u2014 files you create are directly accessible to desktop applications and vice versa."
        b':"**Separate filesystems.** Computer-use actions (clicks, typing, clipboard writes) happen on the user\\u2019s '
        b"real computer \\u2014 a different system from your sandbox."
        b'")'
    )
    # This approach won't work because the text is inside a template literal, not JS code.
    # Instead, we do a simple string replacement: replace the entire paragraph on Linux
    # by wrapping with a runtime check injected AFTER the template is built.
    #
    # Better approach: replace the literal text with platform-conditional text using
    # the same pattern as sub-patch 13 (inject ternary into the JS source).

    # Actually, the cleanest approach: since this text is inside template literals
    # (backtick strings), we replace the literal macOS-specific text with
    # platform-conditional expressions using ${} interpolation.

    _sep_old_full = b"**Separate filesystems.** Computer-use actions (clicks, typing, clipboard writes) happen on the user\\u2019s real computer \\u2014 a different system from your sandbox. "

    # Check what the actual bytes are (the template literal uses real Unicode, not escapes)
    _sep_old_full2 = b"**Separate filesystems.** Computer-use actions (clicks, typing, clipboard writes) happen on the user's real computer \xe2\x80\x94 a different system from your sandbox. "

    _sep_count = content.count(_sep_old_full2)
    if _sep_count >= 2:
        _sep_new_full = (
            b'${process.platform==="linux"?(globalThis.__cuKwinMode'
            b'?"**Same filesystem.** Computer-use actions and your CLI tools operate on the same Linux machine. '
            b"Files you create are directly accessible to desktop applications, and files selected or edited in "
            b"desktop apps are on the same machine you can read from the CLI. "
            b'"'
            b':"**Same filesystem.** Computer-use actions and your CLI tools operate on the same Linux machine. '
            b"There is no sandbox \\u2014 files you create are directly accessible to desktop applications and vice versa. "
            b'")'
            b':"**Separate filesystems.** Computer-use actions (clicks, typing, clipboard writes) '
            b"happen on the user's real computer \xe2\x80\x94 a different system from your sandbox. "
            b'"}'
        )
        content = content.replace(_sep_old_full2, _sep_new_full)
        print(f"  [OK] 14a separate filesystems: 3-way replace, {_sep_count} occurrences")
        changes += _sep_count
        patches_applied += 1
    else:
        print(f"  [FAIL] 14a separate filesystems: expected 2 occurrences, found {_sep_count}")

    # 14b: Replace macOS app names with generic Linux terms (1 occurrence in CCD template)
    _apps_old = b"Maps, Notes, Finder, Photos, System Settings"
    _apps_new = b'${process.platform==="linux"?"the file manager, image viewer, terminal emulator, system settings":"Maps, Notes, Finder, Photos, System Settings"}'

    if _apps_old in content:
        content = content.replace(_apps_old, _apps_new, 1)
        print("  [OK] 14b app names: replaced macOS apps with Linux-generic terms")
        changes += 1
        patches_applied += 1
    else:
        print("  [FAIL] 14b app names: 'Maps, Notes, Finder, Photos, System Settings' not found")

    # 14c: File manager name in host filesystem request_cowork_directory hint.
    # 3-way: kwin-wayland=Dolphin, regular=Files, non-Linux=Finder.
    _fm_old = b'"File Explorer":"Finder"'
    _fm_new = b'"File Explorer":process.platform==="linux"?(globalThis.__cuKwinMode?"Dolphin":"Files"):"Finder"'

    if _fm_old in content:
        content = content.replace(_fm_old, _fm_new, 1)
        print("  [OK] 14c file manager name: 3-way (kwin-wayland=Dolphin, regular=Files, other=Finder)")
        changes += 1
        patches_applied += 1
    else:
        print("  [FAIL] 14c file manager name: pattern not found")

    # 14d (kwin-wayland): Append explicit Linux/KDE environment hint to the CU
    # system-prompt intro. kwin-wayland only — regular mode keeps the upstream
    # sentence unchanged so non-KDE users aren't misled. We rewrite the anchor as
    # a template ternary on globalThis.__cuKwinMode so runtime mode selects.
    env_prompt_anchor_esc = (
        r"You have a computer-use MCP available \(tools named \\\`mcp__computer-use__\*\\\`\)\. It lets you take screenshots of the user's desktop and control it with mouse clicks, keyboard input, and scrolling\."
    )
    env_prompt_pattern = env_prompt_anchor_esc.encode("utf-8")
    env_prompt_matches = [m.start() for m in re.finditer(env_prompt_pattern, content)]
    if env_prompt_matches:
        env_prompt_new = (
            b"You have a computer-use MCP available (tools named \\`mcp__computer-use__*\\`). It lets you take "
            b"screenshots of the user's desktop and control it with mouse clicks, keyboard input, and scrolling."
            b"${globalThis.__cuKwinMode?' This computer is running Linux with KDE Plasma. The desktop shell is "
            b"plasmashell. The file manager is Dolphin.':''}"
        )
        content, env_prompt_count = re.subn(env_prompt_pattern, env_prompt_new, content)
        if env_prompt_count > 0:
            print(
                f"  [OK] 14d CU env prompt: kwin-wayland-only KDE suffix ({env_prompt_count} occurrence{'s' if env_prompt_count != 1 else ''})"
            )
            changes += env_prompt_count
            patches_applied += 1
        else:
            print("  [FAIL] 14d CU env prompt: replace failed")
    else:
        print("  [FAIL] 14d CU env prompt: environment sentence anchor not found")

    if patches_applied < EXPECTED_PATCHES:
        print(f"  [FAIL] Only {patches_applied}/{EXPECTED_PATCHES} patches applied — check [FAIL] messages above")
        # Still write partial changes so the build can be inspected
        if content != original_content:
            with open(filepath, "wb") as f:
                f.write(content)
        return False

    if content != original_content:
        with open(filepath, "wb") as f:
            f.write(content)
        print(f"  [PASS] {patches_applied}/{EXPECTED_PATCHES} sub-patches applied ({changes} content changes)")
        return True
    else:
        print("  [FAIL] No changes made")
        return False


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_computer_use_linux(sys.argv[1])
    sys.exit(0 if success else 1)
