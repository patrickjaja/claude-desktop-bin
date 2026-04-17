#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Enable Cowork on Linux with runtime backend selection.

The claude-cowork-service daemon can run in either "native" mode (executes
Claude Code directly on the host; no VM) or "kvm" mode (boots a QEMU/KVM
guest using the Windows VM bundle artefacts). Each mode creates a different
Unix socket so Claude Desktop can auto-detect which one is running:

    native → $XDG_RUNTIME_DIR/cowork-vm-service.sock
    kvm    → $XDG_RUNTIME_DIR/cowork-kvm-service.sock

Runtime selection precedence (evaluated in the bundle preamble, below):
  1. Explicit COWORK_VM_BACKEND env var wins (values: "native" / "kvm",
     anything else falls through to native).
  2. Auto-detect: if the kvm socket exists, run in kvm mode.
  3. Fallback: native.

The choice is stored on globalThis.__coworkKvmMode. Patches gate behavior on
it via JS ternaries so a single patched bundle runs either backend based on
what the user has started.

Patches:
  0. Mode preamble — detects backend + sets globalThis.__coworkKvmMode.
  A. VM client loader — extend Li (win32 check) to include Linux so the
     TypeScript VM client loads instead of the macOS Swift module.
  B. Socket path — replace Windows named pipe with the Linux Unix socket
     (kvm name vs native name picked at runtime).
  C. Bundle config — two edits that cooperate:
       C1) inject ",linux:{x64:[]}" so native mode sees an empty file list
           (C$() vacuously true → z2e() sets status=Ready, no download),
       C2) alias linux→win32 at the two Xs.files[process.platform] lookup
           sites *only when kvm mode is active*, so kvm downloads the same
           VM artefacts Windows does (rootfs.vhdx, vmlinuz, initrd).
  D. pathToClaudeCodeExecutable — dynamic resolution on Linux.
  E. Error detection — extend "/usr/local/bin/claude" includes check to
     match the Linux paths too.
  F. present_files — allow host outputs dir paths on native backend.
  G. vmProcessId guards — remove the early-return guards that fire after
     idle teardown; the daemon handles mountPath/delete-permission without
     needing vmProcessId. Applied unconditionally (upstream bug affecting
     both backends).
  H. smol-bin copy — gate the "copy smol-bin.vhdx into session dir" step so
     it runs on Linux *only in kvm mode* (native has no VM to boot).

Patches always run on clean, freshly-extracted bundles. There are NO
"already patched" fast paths — a missing anchor is a hard failure so we
notice upstream churn immediately.

Usage: python3 fix_cowork_linux.py <path_to_index.js>
"""

import sys
import os
import re


EXPECTED_PATCHES = 11  # preamble + A + B + C1 + C2 + D + E + F + G-mount + G-delete + H


# Runtime mode selector JS snippet, loaded from the sibling file that both
# this script and the Nim port share. Keeping the source on disk as plain
# .js (rather than a Python string constant) means there's one canonical
# copy — no codegen step, no drift between Python and Nim implementations.
_HERE = os.path.dirname(os.path.abspath(__file__))
with open(os.path.join(_HERE, "../js/cowork_mode_preamble.js"), "rb") as _f:
    MODE_PREAMBLE_JS = _f.read()


def patch_cowork_linux(filepath):
    """Enable Cowork VM features on Linux with runtime native/kvm switching."""

    print("=== Patch: fix_cowork_linux ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, "rb") as f:
        content = f.read()

    patches_applied = 0

    # ── Patch 0: Mode preamble at file start (right after "use strict";) ──
    #
    # Must run before any module-level const that contains a template
    # literal with ${globalThis.__coworkKvmMode?…} — sandbox_refs B/C wrap
    # substrings inside such templates, and those templates are constructed
    # as soon as their enclosing function/object initializer runs (which
    # can happen during module load, before app.on("ready") would fire).
    strict_marker = b'"use strict";'
    strict_idx = content.find(strict_marker)
    if strict_idx == 0:
        insertion_point = len(strict_marker)
        content = content[:insertion_point] + MODE_PREAMBLE_JS + content[insertion_point:]
        print('  [OK] 0 mode preamble: injected after "use strict"')
        patches_applied += 1
    else:
        print('  [FAIL] 0 mode preamble: "use strict"; not at file start')

    # ── Patch A: VM client loader — extend Li check to include Linux ───
    vm_client_pattern = rb'([\w$]+)\?([\w$]+)=(\{vm:[\w$]+\}):\2=\(await import\("@ant/claude-swift"\)\)\.default'

    def vm_client_replacement(m):
        li_var = m.group(1)
        ef_var = m.group(2)
        vm_obj = m.group(3)
        return b"(" + li_var + b'||process.platform==="linux")?' + ef_var + b"=" + vm_obj + b":" + ef_var + b'=(await import("@ant/claude-swift")).default'

    content, count_a = re.subn(vm_client_pattern, vm_client_replacement, content)
    if count_a >= 1:
        print(f"  [OK] A VM client loader: extended to Linux ({count_a} match)")
        patches_applied += 1
    else:
        print("  [FAIL] A VM client loader: 0 matches")

    # ── Patch B: Socket path — mode-aware Unix socket on Linux ──────
    pipe_path = b'"\\\\\\\\.\\\\pipe\\\\cowork-vm-service"'
    pipe_search = b"=" + pipe_path

    if pipe_search in content:
        idx = content.index(pipe_search)
        start = idx - 1
        while start >= 0 and (content[start : start + 1].isalnum() or content[start : start + 1] in (b"_", b"$")):
            start -= 1
        start += 1
        var_name = content[start:idx]

        replacement = (
            var_name
            + b'=process.platform==="linux"?'
            + b'(process.env.XDG_RUNTIME_DIR||"/tmp")+(globalThis.__coworkKvmMode?"/cowork-kvm-service.sock":"/cowork-vm-service.sock")'
            + b":"
            + pipe_path
        )
        content = content[:start] + replacement + content[idx + len(pipe_search) :]
        print(f"  [OK] B socket path: runtime-selected Unix socket on Linux (var={var_name.decode()})")
        patches_applied += 1
    else:
        print("  [FAIL] B socket path: pipe path not found")

    # ── Patch C1: Inject ",linux:{x64:[]}" into bundle files config ──
    win32_marker = b"win32:{"
    win32_idx = content.find(win32_marker)
    c1_ok = False
    if win32_idx >= 0:
        x64_marker = b",x64:["
        x64_idx = content.find(x64_marker, win32_idx)
        if x64_idx >= 0:
            array_start = x64_idx + len(x64_marker) - 1
            depth = 0
            pos = array_start
            while pos < len(content):
                if content[pos : pos + 1] == b"[":
                    depth += 1
                elif content[pos : pos + 1] == b"]":
                    depth -= 1
                    if depth == 0:
                        break
                pos += 1

            after_array = pos + 1
            if content[after_array : after_array + 1] == b"}":
                inject = b",linux:{x64:[]}"
                content = content[: after_array + 1] + inject + content[after_array + 1 :]
                print("  [OK] C1 bundle config: linux platform added (empty file list)")
                patches_applied += 1
                c1_ok = True
            else:
                print("  [FAIL] C1 bundle config: unexpected structure after x64 array")
        else:
            print("  [FAIL] C1 bundle config: x64 array not found in win32 block")
    else:
        print("  [FAIL] C1 bundle config: win32 block not found")

    # ── Patch C2: Alias linux→win32 at the Xs.files[…] lookup sites
    #             (runtime-gated on globalThis.__coworkKvmMode). ─────
    bundle_lookup_re = re.compile(
        rb"(const ([\w$]+)=)process\.platform"
        rb"(,[\w$]+=[\w$]+\(\);return [\w$]+\.files\[\2\])"
    )

    def bundle_lookup_replacement(m):
        return (
            m.group(1)
            + b'(globalThis.__coworkKvmMode?(process.platform==="linux"?"win32":process.platform):process.platform)'
            + m.group(3)
        )

    content, c2_count = bundle_lookup_re.subn(bundle_lookup_replacement, content)
    if c2_count >= 1:
        print(f"  [OK] C2 bundle lookup alias: linux→win32 when kvm mode ({c2_count} site(s))")
        patches_applied += 1
    else:
        print("  [FAIL] C2 bundle lookup alias: no matching sites found")

    # Silence unused variable warning on c1_ok — kept for readability.
    del c1_ok

    # ── Patch D: pathToClaudeCodeExecutable — dynamic on Linux ──────
    claude_path_old = b'pathToClaudeCodeExecutable:"/usr/local/bin/claude"'
    claude_path_new = (
        b"pathToClaudeCodeExecutable:"
        b'(()=>{if(process.platform!=="linux")return"/usr/local/bin/claude";'
        b'const fs=require("fs");'
        b'for(const p of["/usr/bin/claude",'
        b'(process.env.HOME||"")+"/.local/bin/claude",'
        b'"/usr/local/bin/claude"])'
        b"if(fs.existsSync(p))return p;"
        b'try{return require("child_process").execSync("which claude",{encoding:"utf-8"}).trim()}'
        b"catch(e){}"
        b'return"claude"})()'
    )

    if claude_path_old in content:
        content = content.replace(claude_path_old, claude_path_new, 1)
        print("  [OK] D Claude Code path: dynamic resolution on Linux")
        patches_applied += 1
    else:
        print("  [FAIL] D Claude Code path: pattern not found")

    # ── Patch E: Error detection — extend Linux paths ───────────────
    error_detect_pattern = rb'([\w$]+)(\.includes\("/usr/local/bin/claude"\))'

    def error_detect_replacement(m):
        var = m.group(1)
        return b"(" + var + b'.includes("/usr/local/bin/claude")||' + var + b'.includes("/usr/bin/claude")||' + var + b'.includes("/.local/bin/claude"))'

    content, error_count = re.subn(error_detect_pattern, error_detect_replacement, content, count=1)
    if error_count >= 1:
        print("  [OK] E error detection: extended for Linux paths")
        patches_applied += 1
    else:
        print("  [FAIL] E error detection: pattern not found")

    # ── Patch F: present_files — allow host outputs dir paths ───────
    present_files_old_pattern = (
        rb"for\(const\{file_path:([\w$]+),vmPath:([\w$]+)\}of ([\w$]+)\)\{"
        rb"if\(([\w$]+)\(\2,([\w$]+)\.vmProcessName\)\)continue;"
        rb"\(([\w$]+)\?([\w$]+)\(\2,\6\):null\)===null&&([\w$]+)\.push\(\1\)\}"
    )

    def present_files_replacement(m):
        f_var = m.group(1)
        p_var = m.group(2)
        l_var = m.group(3)
        scratchpad_fn = m.group(4)
        t_var = m.group(5)
        c_var = m.group(6)
        resolve_fn = m.group(7)
        u_var = m.group(8)
        return (
            b"for(const{file_path:" + f_var + b",vmPath:" + p_var + b"}of " + l_var + b"){"
            b"if(" + scratchpad_fn + b"(" + p_var + b"," + t_var + b".vmProcessName))continue;"
            b"(" + c_var + b"?" + resolve_fn + b"(" + p_var + b"," + c_var + b"):null)===null&&"
            b"(()=>{const _ho=" + t_var + b".getHostOutputsDir();"
            b"if(_ho&&(" + f_var + b"===_ho||" + f_var + b'.startsWith(_ho+"/")))return;' + u_var + b".push(" + f_var + b")})()}"
        )

    content, count_f = re.subn(present_files_old_pattern, present_files_replacement, content)
    if count_f >= 1:
        print(f"  [OK] F present_files: host outputs dir allowed ({count_f} match)")
        patches_applied += 1
    else:
        print("  [FAIL] F present_files: pattern not found")

    # ── Patch G-mount: remove mountFolderForSession vmProcessId guard ──
    mount_guard_re = re.compile(
        rb"if\s*\(\s*!\s*[a-zA-Z_$][\w$]*\s*\|\|\s*!\s*[a-zA-Z_$][\w$]*\s*\)"
        rb"\s*return\s*\{\s*ok\s*:\s*!\s*1\s*,\s*error\s*:\s*"
        rb'"Session VM process not available\. '
        rb'The session may not be fully initialized\."\s*\}\s*;?'
    )
    content, mount_n = mount_guard_re.subn(b"", content)
    if mount_n >= 1:
        print(f"  [OK] G-mount vmProcessId guard: removed ({mount_n} match)")
        patches_applied += 1
    else:
        print("  [FAIL] G-mount vmProcessId guard: pattern not found")

    # ── Patch G-delete: remove delete-permission tool vmProcessId guard ─
    delete_guard_re = re.compile(
        rb"if\s*\(\s*!\s*[a-zA-Z_$][\w$]*\s*\)\s*return\s*\{\s*content\s*:"
        rb"\s*\[\s*\{\s*type\s*:\s*\"text\"\s*,\s*text\s*:\s*"
        rb'"Session VM process not available\. '
        rb'The session may not be fully initialized\."\s*\}\s*\]\s*,'
        rb"\s*isError\s*:\s*!\s*0\s*\}\s*;?"
    )
    content, delete_n = delete_guard_re.subn(b"", content)
    if delete_n >= 1:
        print(f"  [OK] G-delete vmProcessId guard: removed ({delete_n} match)")
        patches_applied += 1
    else:
        print("  [FAIL] G-delete vmProcessId guard: pattern not found")

    # ── Patch H: smol-bin copy gate — runtime-gated on kvm mode ─────
    smol_bin_gate_re = re.compile(
        rb'if\(process\.platform==="win32"\)(\{const [\w$]+=[\w$]+\(\),'
        rb'[\w$]+=[\w$]+\.join\(process\.resourcesPath,`smol-bin\.)'
    )
    content, smol_n = smol_bin_gate_re.subn(
        rb'if(process.platform==="win32"||process.platform==="linux"&&globalThis.__coworkKvmMode)\1',
        content,
    )
    if smol_n >= 1:
        print(f"  [OK] H smol-bin copy gate: kvm-mode Linux opt-in ({smol_n} match)")
        patches_applied += 1
    else:
        print("  [FAIL] H smol-bin copy gate: win32 gate pattern not found")

    # ── Checks ───────────────────────────────────────────────────────
    if patches_applied < EXPECTED_PATCHES:
        print(f"  [FAIL] Only {patches_applied}/{EXPECTED_PATCHES} patches applied — check [WARN]/[FAIL] messages above")
        return False

    with open(filepath, "wb") as f:
        f.write(content)
    print(f"  [PASS] {patches_applied} patches applied")
    return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_cowork_linux(sys.argv[1])
    sys.exit(0 if success else 1)
