#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Enable Dispatch (remote task orchestration) on Linux.

Dispatch lets users send tasks from mobile to desktop. It's blocked on Linux
by two GrowthBook server-side feature flags and two platform checks.

Six-part patch (A–F):
A. Force sessions-bridge init gate ON.
   The code uses `let f=!1` and a GrowthBook callback for flag "3572572142"
   (yukon_silver_cuttlefish_desktop) to set f=true. On Linux the flag never
   fires from the server. We force f=!0 so the bridge always initializes.

B. Bypass remote session control check.
   Two call sites check `!Jr("2216414644")` and throw
   "Remote session control is disabled" if the flag is off. We replace
   the check with `!1` (false) so the throw is never reached.

C. Add Linux to the HI() platform label.
   HI() returns "Unsupported Platform" for anything that's not macOS/Windows.
   We add `case"linux":return"Linux"` so the UI shows a proper label.

D. Include Linux in the Xqe telemetry gate.
   `Xqe = Hr || Pn` (darwin || win32) gates the $t() telemetry reporter.
   Without Linux, dispatch telemetry events silently drop. We extend the
   check to include Linux.

E. Override Jr() for Linux-critical GrowthBook flags.
   Two flags are force-enabled on Linux:
   - "3558849738": Controls Lv() → agentNameEnabled in the bridge status
     store. When false, the web frontend hides Dispatch entirely.
   - "1143815894": Controls hostLoopMode (non-VM cowork). When true,
     sessions run the CLI directly on the host instead of in a VM. Linux
     has no VM infrastructure — we always use native cowork via the Go
     daemon, so host-loop mode is semantically correct and avoids
     unnecessary VM path translations.
   We inject checks at the top of Jr() to return true for both flags.

F. Fix sessions-bridge event filter to forward text responses.
   The rjt() function in the sessions-bridge determines which assistant
   messages are forwarded to the API. It only forwards messages containing
   a SendUserMessage tool_use block, dropping plain text responses. We
   patch rjt() to also return true for text content, mcp__dispatch__send_message,
   and mcp__cowork__present_files tool_use blocks.

G–I. (Removed) Diagnostic logging and synthetic SendUserMessage transform
     — no longer needed.

Usage: python3 fix_dispatch_linux.py <path_to_index.js>
"""

import sys
import os
import re


def patch_dispatch_linux(filepath):
    """Enable Dispatch remote task orchestration on Linux."""

    print("=== Patch: fix_dispatch_linux ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, "rb") as f:
        content = f.read()

    original_content = content
    patches_applied = 0

    # ── Patch A: Force sessions-bridge init gate ON ──────────────────────
    #
    # Original code:
    #   let f=!1;
    #   const h=async()=>{
    #     if(!f){T.info("[sessions-bridge] init skipped — gate off ..."); return}
    #     await eqt({sessionManager:r, ...})
    #   };
    #   ...
    #   yx("3572572142", _=>{f=!!(_!=null&&_.on), g()});
    #
    # The GrowthBook callback for flag 3572572142 sets f=true when the flag
    # is on. On Linux, the flag never fires. We force f=!0 (true) from the
    # start so the bridge initializes unconditionally.
    #
    # Pattern uses \w+ for all minified variable names. The gate variable
    # is the LAST in a comma-separated `let` declaration before `;const`.
    # In v1.1.8359 it was a single var: `let f=!1;const h=...`
    # In v1.1.8629 it's three vars: `let f=!1,p=!1,h=!1;const y=...`
    # The backreference (\2) ensures the captured gate var matches the
    # one in the if-check.

    gate_pattern = rb'(let (?:[\w$]+=!1,)*)([\w$]+)(=)(!1)(;const [\w$]+=async\(\)=>\{if\(!\2\)\{[\w$]+\.info\("\[sessions-bridge\] init skipped)'

    def gate_replacement(m):
        return m.group(1) + m.group(2) + m.group(3) + b"!0" + m.group(5)

    # Check if already patched (gate var=!0 instead of =!1)
    gate_already = rb'let (?:[\w$]+=!(?:0|1),)*[\w$]+=!0;const [\w$]+=async\(\)=>\{if\(![\w$]+\)\{[\w$]+\.info\("\[sessions-bridge\] init skipped'
    if re.search(gate_already, content):
        print("  [OK] Sessions-bridge gate: already patched (skipped)")
        patches_applied += 1
    else:
        content, count_a = re.subn(gate_pattern, gate_replacement, content)
        if count_a >= 1:
            print(f"  [OK] Sessions-bridge gate: forced ON ({count_a} match)")
            patches_applied += 1
        else:
            print("  [FAIL] Sessions-bridge gate: pattern not found")

    # ── Patch B: Bypass remote session control check ─────────────────────
    #
    # Two call sites in the session manager:
    #   if(e.channel==="mobile"&&!Jr("2216414644"))
    #     throw new Error("Remote session control is disabled");
    #
    # Jr() reads the GrowthBook flag value. !Jr("2216414644") is true when
    # the flag is off (i.e., blocks remote control). On Linux the flag is
    # never set.
    #
    # We replace `!Jr("2216414644")` with `!1` (which is JS `false`), so
    # the condition `channel==="mobile" && false` never throws.
    #
    # Pattern uses \w+ for the Jr function name (minified, may change).

    remote_pattern = rb'![\w$]+\("2216414644"\)'

    # Check if already patched (no Jr("2216414644") calls remain)
    if not re.search(remote_pattern, content):
        # Verify the throw sites still exist (meaning we patched, not that code changed)
        if b"Remote session control is disabled" in content:
            print("  [OK] Remote session control: already patched (skipped)")
            patches_applied += 1
        else:
            print("  [FAIL] Remote session control: pattern not found")
    else:
        content, count_b = re.subn(remote_pattern, b"!1", content)
        if count_b >= 1:
            print(f"  [OK] Remote session control: bypassed ({count_b} matches)")
            patches_applied += 1
        else:
            print("  [FAIL] Remote session control: pattern not found")

    # ── Patch C: Add Linux to HI() platform label ───────────────────────
    #
    # Original:
    #   HI=()=>{switch(process.platform){
    #     case"darwin":return"macOS";
    #     case"win32":return"Windows";
    #     default:return"Unsupported Platform"
    #   }}
    #
    # We insert `case"linux":return"Linux";` before the default branch so
    # the dispatch UI shows "Linux" instead of "Unsupported Platform".

    platform_old = b'default:return"Unsupported Platform"'
    platform_new = b'case"linux":return"Linux";default:return"Unsupported Platform"'

    if platform_new in content:
        print("  [OK] Platform label: already patched (skipped)")
        patches_applied += 1
    elif platform_old in content:
        content = content.replace(platform_old, platform_new, 1)
        print("  [OK] Platform label: added Linux to HI()")
        patches_applied += 1
    else:
        print("  [FAIL] Platform label: pattern not found")

    # ── Patch D: Include Linux in Xqe telemetry gate ────────────────────
    #
    # Original:
    #   Hr=process.platform==="darwin",Pn=process.platform==="win32",Xqe=Hr||Pn
    #
    # The $t() telemetry function bails early with `if(!Xqe)return`, so on
    # Linux all dispatch telemetry events are silently dropped. We extend
    # the gate to include Linux.
    #
    # Pattern captures the darwin/win32 variable names via backreferences
    # to ensure the same names appear in the combined expression.

    telemetry_pattern = rb'([\w$]+)(=process\.platform==="darwin",)([\w$]+)(=process\.platform==="win32",)([\w$]+)=\1\|\|\3'

    # Check if already patched (linux check already appended)
    telemetry_already = rb'([\w$]+)(=process\.platform==="darwin",)([\w$]+)(=process\.platform==="win32",)([\w$]+)=\1\|\|\3\|\|process\.platform==="linux"'
    if re.search(telemetry_already, content):
        print("  [OK] Telemetry gate: already patched (skipped)")
        patches_applied += 1
    else:

        def telemetry_replacement(m):
            return m.group(0) + b'||process.platform==="linux"'

        content, count_d = re.subn(telemetry_pattern, telemetry_replacement, content)
        if count_d >= 1:
            print(f"  [OK] Telemetry gate: included Linux ({count_d} match)")
            patches_applied += 1
        else:
            print("  [FAIL] Telemetry gate: pattern not found")

    # ── Patch E: Override Jr() for dispatch agent name flag ──────────────
    #
    # Jr() is the GrowthBook flag reader:
    #   function Jr(t){const e=Cl[t];return(e==null?void 0:e.on)??!1}
    #
    # Flag "3558849738" controls Lv() → agentNameEnabled in the bridge
    # status store. When false, the web frontend hides Dispatch entirely.
    # We inject `if(t==="3558849738")return!0;` at the top of Jr() so it
    # returns true for this flag regardless of the server response.
    #
    # Pattern uses \w+ for all minified names. The unique anchor is the
    # Cl[t] lookup + nullish coalescing chain.

    # Only override "3558849738" (dispatch agent name). Do NOT override
    # "1143815894" (hostLoopMode) — that flag forces HostLoop mode which
    # bypasses the cowork service spawn, breaking skills/plugins.
    jr_target = b'if(t==="3558849738")return!0;'
    jr_stale_both = b'if(t==="3558849738"||t==="1143815894")return!0;'
    if jr_stale_both in content:
        # Downgrade: remove the hostLoopMode override added in error
        content = content.replace(jr_stale_both, jr_target, 1)
        print("  [OK] Jr() dispatch flag override: removed stale hostLoopMode override")
        patches_applied += 1
    elif jr_target in content:
        print("  [OK] Jr() dispatch flag override: already patched (skipped)")
        patches_applied += 1
    else:
        # Match: function Jr(t){const e=Cl[t];return(e==null?void 0:e.on)??!1}
        jr_pattern = rb"(function )([\w$]+)(\()([\w$]+)(\)\{)(const [\w$]+=[\w$]+\[\4\];return\([\w$]+==null\?void 0:[\w$]+\.on\)\?\?!1\})"

        # Remove stale blanket override if present from previous builds
        blanket_marker = rb"(return!0;)(const [\w$]+=[\w$]+\[[\w$]+\];return)"
        content = re.sub(blanket_marker, rb"\2", content)

        def jr_replacement(m):
            param = m.group(4)
            return m.group(1) + m.group(2) + m.group(3) + m.group(4) + m.group(5) + b"if(" + param + b'==="3558849738")return!0;' + m.group(6)

        content, count_e = re.subn(jr_pattern, jr_replacement, content)
        if count_e >= 1:
            print(f"  [OK] Jr() dispatch flag override: injected ({count_e} match)")
            patches_applied += 1
        else:
            print("  [FAIL] Jr() dispatch flag override: pattern not found")

    # ── Patch F: Fix rjt() to forward text responses ────────────────────
    #
    # The rjt() function filters which assistant messages the sessions-bridge
    # forwards to the API. Currently, only messages with a SendUserMessage
    # tool_use block pass the filter. Plain text responses are dropped:
    #
    #   function rjt(t){
    #     ...
    #     if(e==="assistant"){
    #       ...
    #       for(const i of n){
    #         const s=i;
    #         if((s==null?void 0:s.type)==="tool_use"&&s.name==="SendUserMessage")return!0
    #       }
    #       return!1   // <-- plain text drops here
    #     }
    #   }
    #
    # We change `return!1}return` (the final false for assistant) to also
    # check for text content blocks:
    #   return n.some(i=>i&&i.type==="text"&&i.text)}return
    #
    # This ensures that when the dispatch orchestrator responds with plain
    # text instead of SendUserMessage, the response still reaches the API
    # and is displayed in the web UI.

    # Flexible pattern: item var (s→n in v1.1.8629→newer) and array var are captured.
    # Original shape:
    #   for(const LOOP of ARRAY){const ITEM=LOOP;if((ITEM==null?void 0:ITEM.type)==="tool_use"
    #     &&ITEM.name==="SendUserMessage")return!0}return!1}
    rjt_pattern = re.compile(
        rb"for\(const ([\w$]+) of ([\w$]+)\)\{const ([\w$]+)=\1;"
        rb'if\(\(\3==null\?void 0:\3\.type\)==="tool_use"&&\3\.name==="SendUserMessage"\)return!0\}return!1\}'
    )

    # Already-patched marker: post-patch we emit `.some(function(j){return j&&j.type==="text"&&j.text})`
    rjt_already = re.compile(
        rb'if\(\(([\w$]+)==null\?void 0:\1\.type\)==="tool_use"&&'
        rb'\(\1\.name==="SendUserMessage"\|\|\1\.name==="mcp__dispatch__send_message"\|\|\1\.name==="mcp__cowork__present_files"\)\)return!0\}'
        rb'return [\w$]+\.some\(function\(j\)\{return j&&j\.type==="text"&&j\.text\}\)\}'
    )

    if rjt_already.search(content):
        print("  [OK] rjt() text forward: already patched (skipped)")
        patches_applied += 1
    else:
        m = rjt_pattern.search(content)
        if m:
            loop_var = m.group(1)
            array_var = m.group(2)
            item_var = m.group(3)
            rjt_replacement = (
                b"for(const "
                + loop_var
                + b" of "
                + array_var
                + b"){const "
                + item_var
                + b"="
                + loop_var
                + b";"
                + b"if(("
                + item_var
                + b"==null?void 0:"
                + item_var
                + b'.type)==="tool_use"&&('
                + item_var
                + b'.name==="SendUserMessage"||'
                + item_var
                + b'.name==="mcp__dispatch__send_message"||'
                + item_var
                + b'.name==="mcp__cowork__present_files"))return!0}'
                + b"return "
                + array_var
                + b'.some(function(j){return j&&j.type==="text"&&j.text})}'
            )
            content = content[: m.start()] + rjt_replacement + content[m.end() :]
            print(f"  [OK] rjt() text forward: patched (item={item_var.decode()}, array={array_var.decode()})")
            patches_applied += 1
        else:
            print("  [FAIL] rjt() text forward: pattern not found")

    # ── Patch G: (Removed) ──────────────────────────────────────────────
    # Diagnostic forwardEvent logging was here. Removed — no longer needed.
    # The forwardEvent function uses its original unpatched code.

    # ── Patch H: (Removed) ──────────────────────────────────────────────
    # Diagnostic writeEvent logging was here. Removed — no longer needed.
    # The writeEvent function uses its original unpatched code.

    # ── Patch I: (Removed) ────────────────────────────────────────────────
    # Synthetic SendUserMessage transform was here. Removed — no longer needed.

    # ── Patch J: Auto-wake dispatch parent when child task completes ─────
    #
    # When the dispatch orchestrator fires start_task, it goes idle.
    # The child runs independently. When the child completes, the session
    # manager queues a notification for the "cold" parent, but nothing
    # triggers the parent to start a new turn to process it.
    #
    # On Windows/Mac, the sessions API likely sends a wake event.
    # On Linux, the parent stays idle until the user sends another message.
    #
    # Fix: after queuing the notification, schedule a sendMessage call
    # on the parent session. sendMessage auto-starts idle sessions,
    # which creates the inputStream and drains pending notifications.
    # The model then reads the child's transcript and delivers the answer.

    # Flexible pattern. Variables have been renamed across versions:
    #   v1.1.8359: session=n, notif=s, child=e, index=r, logger=B
    #   v1.1.8629: same + logger=P
    #   v1.1.87xx: session=i, notif=n, child=A, index=t, logger=M
    # We capture all four via backreferences.
    wake_pattern = re.compile(
        rb"(\(\(([\w$]+)\.pendingDispatchNotifications\?\?\(\2\.pendingDispatchNotifications=\[\]\)\)\.push\(([\w$]+)\),)"
        rb"([\w$]+)"  # logger variable (group 4)
        rb"(\.info\(`\[Dispatch\] Queued notification for cold parent \$\{\2\.sessionId\} \(child \$\{([\w$]+)\.sessionId\} \$\{([\w$]+)\}\)`\)\))"
    )

    # Check if already patched (has setTimeout auto-wake)
    if b"Auto-waking cold parent" in content:
        print("  [OK] dispatch auto-wake parent: already patched (skipped)")
        patches_applied += 1
    else:
        wake_match = wake_pattern.search(content)
        if wake_match:
            session_var = wake_match.group(2)
            notif_var = wake_match.group(3)
            logger = wake_match.group(4)
            wake_replacement = (
                wake_match.group(1)
                + logger
                + wake_match.group(5)[:-1]  # strip trailing )
                + b",setTimeout(()=>{"
                + logger
                + b".info(`[Dispatch] Auto-waking cold parent ${"
                + session_var
                + b".sessionId}`);"
                + b"this.sendMessage("
                + session_var
                + b".sessionId,"
                + notif_var
                + b").catch(x=>"
                + logger
                + b".error(`[Dispatch] Auto-wake failed for ${"
                + session_var
                + b".sessionId}:`,x))},500))"
            )
            content = content[: wake_match.start()] + wake_replacement + content[wake_match.end() :]
            print(f"  [OK] dispatch auto-wake parent: injected setTimeout sendMessage (session={session_var.decode()}, notif={notif_var.decode()}, logger={logger.decode()})")
            patches_applied += 1
        else:
            print("  [FAIL] dispatch auto-wake parent: pattern not found")

    # ── Results ──────────────────────────────────────────────────────────

    EXPECTED_PATCHES = 7  # A, B, C, D, E, F, J — all must succeed or be already patched
    if patches_applied < EXPECTED_PATCHES:
        print(f"  [FAIL] Only {patches_applied}/{EXPECTED_PATCHES} patches applied — check [WARN]/[FAIL] messages above")
        return False

    if content == original_content:
        print(f"  [OK] All {patches_applied} patches already applied (no changes needed)")
        return True

    # Verify our patches didn't introduce a brace imbalance
    original_delta = original_content.count(b"{") - original_content.count(b"}")
    patched_delta = content.count(b"{") - content.count(b"}")
    if original_delta != patched_delta:
        diff = patched_delta - original_delta
        print(f"  [FAIL] Patch introduced brace imbalance: {diff:+d} unmatched braces")
        return False

    # Write back
    with open(filepath, "wb") as f:
        f.write(content)
    print(f"  [PASS] {patches_applied} patches applied")
    return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_dispatch_linux(sys.argv[1])
    sys.exit(0 if success else 1)
