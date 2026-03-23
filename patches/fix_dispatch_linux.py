#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Enable Dispatch (remote task orchestration) on Linux.

Dispatch lets users send tasks from mobile to desktop. It's blocked on Linux
by two GrowthBook server-side feature flags and two platform checks.

Seven-part patch:
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

E. Override Jr() to force-enable dispatch agent name flag.
   Flag "3558849738" controls Lv() which determines if the Dispatch agent
   name feature is active. When false, sessionsBridgeStatusStore reports
   agentNameEnabled:false and the web frontend hides the Dispatch tab.
   We inject a check at the top of Jr() to return true for this flag ID.

F. Fix sessions-bridge event filter to forward text responses.
   The rjt() function in the sessions-bridge determines which assistant
   messages are forwarded to the API. It only forwards messages containing
   a SendUserMessage tool_use block, dropping plain text responses. When
   the dispatch orchestrator replies with plain text (instead of calling
   SendUserMessage), the response is never sent to the API and the web
   UI shows nothing. We patch rjt() to also return true when the message
   contains text content blocks.

G. (Removed) Diagnostic forwardEvent logging — no longer needed.

H. (Removed) Diagnostic writeEvent logging — no longer needed.

I. Transform assistant messages into SendUserMessage tool_use blocks.
   Handles both plain text responses AND mcp__cowork__present_files
   tool_use blocks. Extracts text into the message field and file paths
   into the attachments array of the synthetic SendUserMessage.

Usage: python3 fix_dispatch_linux.py <path_to_index.js>
"""

import sys
import os
import re


def patch_dispatch_linux(filepath):
    """Enable Dispatch remote task orchestration on Linux."""

    print(f"=== Patch: fix_dispatch_linux ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, 'rb') as f:
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
    # Pattern uses \w+ for all minified variable names and a backreference
    # (\2) to ensure the same variable appears in both the declaration and
    # the if-check.

    gate_pattern = rb'(let )(\w+)(=)(!1)(;const \w+=async\(\)=>\{if\(!\2\)\{\w+\.info\("\[sessions-bridge\] init skipped)'

    def gate_replacement(m):
        return m.group(1) + m.group(2) + m.group(3) + b'!0' + m.group(5)

    # Check if already patched (f=!0 instead of f=!1)
    gate_already = rb'let \w+=!0;const \w+=async\(\)=>\{if\(!\w+\)\{\w+\.info\("\[sessions-bridge\] init skipped'
    if re.search(gate_already, content):
        print(f"  [OK] Sessions-bridge gate: already patched (skipped)")
        patches_applied += 1
    else:
        content, count_a = re.subn(gate_pattern, gate_replacement, content)
        if count_a >= 1:
            print(f"  [OK] Sessions-bridge gate: forced ON ({count_a} match)")
            patches_applied += 1
        else:
            print(f"  [FAIL] Sessions-bridge gate: pattern not found")

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

    remote_pattern = rb'!\w+\("2216414644"\)'

    # Check if already patched (no Jr("2216414644") calls remain)
    if not re.search(remote_pattern, content):
        # Verify the throw sites still exist (meaning we patched, not that code changed)
        if b'Remote session control is disabled' in content:
            print(f"  [OK] Remote session control: already patched (skipped)")
            patches_applied += 1
        else:
            print(f"  [FAIL] Remote session control: pattern not found")
    else:
        content, count_b = re.subn(remote_pattern, b'!1', content)
        if count_b >= 1:
            print(f"  [OK] Remote session control: bypassed ({count_b} matches)")
            patches_applied += 1
        else:
            print(f"  [FAIL] Remote session control: pattern not found")

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
        print(f"  [OK] Platform label: already patched (skipped)")
        patches_applied += 1
    elif platform_old in content:
        content = content.replace(platform_old, platform_new, 1)
        print(f"  [OK] Platform label: added Linux to HI()")
        patches_applied += 1
    else:
        print(f"  [WARN] Platform label: pattern not found")

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

    telemetry_pattern = rb'(\w+)(=process\.platform==="darwin",)(\w+)(=process\.platform==="win32",)(\w+)=\1\|\|\3'

    # Check if already patched (linux check already appended)
    telemetry_already = rb'(\w+)(=process\.platform==="darwin",)(\w+)(=process\.platform==="win32",)(\w+)=\1\|\|\3\|\|process\.platform==="linux"'
    if re.search(telemetry_already, content):
        print(f"  [OK] Telemetry gate: already patched (skipped)")
        patches_applied += 1
    else:
        def telemetry_replacement(m):
            return m.group(0) + b'||process.platform==="linux"'

        content, count_d = re.subn(telemetry_pattern, telemetry_replacement, content)
        if count_d >= 1:
            print(f"  [OK] Telemetry gate: included Linux ({count_d} match)")
            patches_applied += 1
        else:
            print(f"  [WARN] Telemetry gate: pattern not found")

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

    jr_already = b'if(t==="3558849738")return!0;'
    if jr_already in content:
        print(f"  [OK] Jr() dispatch flag override: already patched (skipped)")
        patches_applied += 1
    else:
        # Match: function Jr(t){const e=Cl[t];return(e==null?void 0:e.on)??!1}
        jr_pattern = rb'(function )(\w+)(\()(\w+)(\)\{)(const \w+=\w+\[\4\];return\(\w+==null\?void 0:\w+\.on\)\?\?!1\})'

        # Remove stale blanket override if present from previous builds
        blanket_marker = rb'(return!0;)(const \w+=\w+\[\w+\];return)'
        content = re.sub(blanket_marker, rb'\2', content)

        def jr_replacement(m):
            param = m.group(4)
            return (
                m.group(1) + m.group(2) + m.group(3) + m.group(4) + m.group(5) +
                b'if(' + param + b'==="3558849738")return!0;' +
                m.group(6)
            )

        content, count_e = re.subn(jr_pattern, jr_replacement, content)
        if count_e >= 1:
            print(f"  [OK] Jr() dispatch flag override: injected ({count_e} match)")
            patches_applied += 1
        else:
            print(f"  [FAIL] Jr() dispatch flag override: pattern not found")

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

    rjt_old = b'if((s==null?void 0:s.type)==="tool_use"&&s.name==="SendUserMessage")return!0}return!1}'
    rjt_new = b'if((s==null?void 0:s.type)==="tool_use"&&(s.name==="SendUserMessage"||s.name==="mcp__dispatch__send_message"||s.name==="mcp__cowork__present_files"))return!0}return n.some(function(j){return j&&j.type==="text"&&j.text})}'

    if rjt_new in content:
        print(f"  [OK] rjt() text forward: already patched (skipped)")
        patches_applied += 1
    elif rjt_old in content:
        content = content.replace(rjt_old, rjt_new, 1)
        print(f"  [OK] rjt() text forward: patched to include text content")
        patches_applied += 1
    else:
        print(f"  [WARN] rjt() text forward: pattern not found")

    # ── Patch G: (Removed) ──────────────────────────────────────────────
    # Diagnostic forwardEvent logging was here. Removed — no longer needed.
    # The forwardEvent function uses its original unpatched code.

    # ── Patch H: (Removed) ──────────────────────────────────────────────
    # Diagnostic writeEvent logging was here. Removed — no longer needed.
    # The writeEvent function uses its original unpatched code.

    # ── Patch I: Transform assistant messages into SendUserMessage ───────
    #
    # The Claude CLI has a timing bug: isBriefEnabled() returns false when
    # the tool list is built (because FF$() hasn't run yet to set
    # userMsgOptIn). So SendUserMessage is never exposed to the model,
    # even though CLAUDE_CODE_BRIEF=1 is set and --tools includes it.
    #
    # The model responds with plain text, which the bridge now forwards
    # (thanks to Patch F). But the API only renders SendUserMessage
    # tool_use blocks — plain text assistant messages are ignored.
    #
    # Additionally, when the model shares files via mcp__cowork__present_files,
    # the bridge drops those too. We extract file paths from present_files
    # tool_use blocks and include them as attachments in the synthetic
    # SendUserMessage.
    #
    # Fix: In forwardEvent, right before transport.write(o), check if the
    # message is an assistant message without SendUserMessage. If so:
    #   1. Extract text content blocks → combine into message
    #   2. Extract present_files tool_use blocks → file paths → attachments
    #   3. Build synthetic SendUserMessage with message + attachments
    #   4. If only files (no text), use "Shared files" as the message

    transform_old = b'r.transport?await r.transport.write(o):f=!0'
    transform_new = (
        # Async IIFE: transforms text/present_files into SendUserMessage,
        # uploads file attachments to /api/oauth/file_upload for mobile download.
        b'await(async function(){'
        b'if(o.type==="assistant"&&o.message&&Array.isArray(o.message.content)){'
        b'var _ht=o.message.content.some(function(b){return b&&b.type==="tool_use"&&b.name==="SendUserMessage"});'
        b'if(!_ht){'
        b'var _tp=o.message.content.filter(function(b){return b&&b.type==="text"&&b.text});'
        b'var _att=[];'
        b'o.message.content.forEach(function(b){'
        b'if(b&&b.type==="tool_use"&&b.name==="mcp__cowork__present_files"&&b.input&&b.input.files){'
        b'b.input.files.forEach(function(f){if(f.file_path)_att.push(f.file_path)})'
        b'}'
        b'});'
        b'var _ct=_tp.map(function(b){return b.text}).join("\\n");'
        b'if(_ct||_att.length>0){'
        # Upload each attachment file to API
        b'var _uploaded=[];'
        b'for(var _ai=0;_ai<_att.length;_ai++){'
        b'try{'
        b'var _fp=_att[_ai];'
        b'var _fd=await Be.readFile(_fp);'
        b'var _fn=Qe.basename(_fp);'
        b'var _bnd="----FormBoundary"+hn.randomUUID();'
        b'var _body=Buffer.concat([Buffer.from("--"+_bnd+"\\r\\nContent-Disposition: form-data; name=\\"file\\"; filename=\\""+_fn+"\\"\\r\\nContent-Type: application/octet-stream\\r\\n\\r\\n"),_fd,Buffer.from("\\r\\n--"+_bnd+"--\\r\\n")]);'
        b'var _tok=await m_(YE(ZE[To()]));'
        b'if(_tok.ok){'
        b'var _res=await ZH(Pr()+"/api/oauth/file_upload",{method:"POST",headers:{"Authorization":"Bearer "+_tok.token,"Content-Type":"multipart/form-data; boundary="+_bnd},body:_body});'
        b'if(_res.ok){'
        b'var _rj=await _res.json();'
        b'if(_rj.file_uuid){_uploaded.push({file_name:_fn,file_uuid:_rj.file_uuid,file_size:_fd.length,file_type:"application/octet-stream",extracted_content:"",origin:"user_upload"});'
        b'C.info("[DISPATCH-UPLOAD] Uploaded "+_fn+" -> "+_rj.file_uuid)}'
        b'}else{C.warn("[DISPATCH-UPLOAD] Upload failed: "+_res.status)}'
        b'}else{C.warn("[DISPATCH-UPLOAD] No OAuth token")}'
        b'}catch(_ue){C.warn("[DISPATCH-UPLOAD] Error: "+_ue)}'
        b'}'
        # Build synthetic SendUserMessage — paths in input.attachments (string[]),
        # file_uuid metadata in file_attachments at event level
        b'var _inp={message:_ct||"Shared files"};'
        b'if(_att.length>0)_inp.attachments=_att;'
        b'o.message.content=[{type:"tool_use",id:"sbr_"+Date.now()+"_"+Math.random().toString(36).slice(2,8),name:"SendUserMessage",input:_inp}];'
        b'if(_uploaded.length>0)o.file_attachments=_uploaded.map(function(u){return{file_uuid:u.file_uuid,file_name:u.file_name,is_image:!1}});'
        b'C.info("[DISPATCH-TRANSFORM] Wrapped in SendUserMessage: msg="+(_ct||"").slice(0,100)+" attachments="+_att.length+" uploaded="+_uploaded.length)'
        b'}}}'
        b'})();'
        b'r.transport?await r.transport.write(o):f=!0'
    )

    if transform_new in content:
        print(f"  [OK] Text/files→SendUserMessage transform: already patched (skipped)")
        patches_applied += 1
    elif transform_old in content:
        content = content.replace(transform_old, transform_new, 1)
        print(f"  [OK] Text/files→SendUserMessage transform: injected")
        patches_applied += 1
    else:
        print(f"  [WARN] Text/files→SendUserMessage transform: pattern not found")

    # ── Results ──────────────────────────────────────────────────────────

    if patches_applied == 0:
        print("  [FAIL] No patches could be applied")
        return False

    if content == original_content:
        print("  [WARN] No changes made (patterns may have already been applied)")
        return True

    # Verify our patches didn't introduce a brace imbalance
    original_delta = original_content.count(b'{') - original_content.count(b'}')
    patched_delta = content.count(b'{') - content.count(b'}')
    if original_delta != patched_delta:
        diff = patched_delta - original_delta
        print(f"  [FAIL] Patch introduced brace imbalance: {diff:+d} unmatched braces")
        return False

    # Write back
    with open(filepath, 'wb') as f:
        f.write(content)
    print(f"  [PASS] {patches_applied} patches applied")
    return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_dispatch_linux(sys.argv[1])
    sys.exit(0 if success else 1)
