#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Register the computer:// protocol on Linux so cowork file previews work.

Claude Desktop uses computer:// URLs for linking to local files (cowork outputs,
generated documents). On macOS, the OS natively handles computer:// via a
registered URL scheme (CFBundleURLSchemes). On Linux there is no system handler,
so clicking these links shows a white page.

Five-part fix:
  A) Register "computer" as a privileged Electron scheme (before app.ready)
  B) Add a protocol handler that serves local files for computer:// URLs
  C) Convert computer:// → file:// in the shell.openExternal helper (fallback)
  D) Allow computer:// URLs in PreviewContext.isAllowedUrl
  E) Inject click interceptor in mainView.js preload to catch computer:// links

Usage: python3 fix_computer_url_linux.py <path_to_index.js>
"""

import sys
import os
import re


EXPECTED_PATCHES = 5


def patch_computer_url(filepath):
    """Register computer:// protocol and convert URLs for Linux."""

    print("=== Patch: fix_computer_url_linux ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, "rb") as f:
        content = f.read()

    original_content = content
    patches_applied = 0

    already_patched = b'scheme:"computer"'

    # ── Part A: Register computer as a privileged scheme ──────────────
    #
    # Inject {scheme:"computer",privileges:{...}} into the
    # registerSchemesAsPrivileged array, before operon-artifact.
    #
    # Stable anchors: registerSchemesAsPrivileged, "operon-artifact"

    if already_patched in content:
        print("  [OK] Part A (scheme registration): already patched")
        patches_applied += 1
    else:
        pat_a = rb'(registerSchemesAsPrivileged\(\[)(\{scheme:"operon-artifact")'

        def repl_a(m):
            scheme = b'{scheme:"computer",privileges:{standard:!0,secure:!0,supportFetchAPI:!0,stream:!0,bypassCSP:!0}},'
            return m.group(1) + scheme + m.group(2)

        content, count = re.subn(pat_a, repl_a, content)
        if count > 0:
            print(f"  [OK] Part A (scheme registration): {count} match(es)")
            patches_applied += 1
        else:
            print("  [FAIL] Part A (scheme registration): 0 matches")

    # ── Part B: Register protocol handler after app.ready ─────────────
    #
    # Inject a whenReady() handler right after registerSchemesAsPrivileged.
    # The handler serves local files for computer:// URLs via net.fetch.
    #
    # Pattern: ...LLr]);const <var>=<obj>.get("userThemeMode")
    # We inject between "]); " and "const".

    handler_marker = b'protocol.handle("computer"'

    if handler_marker in content:
        print("  [OK] Part B (protocol handler): already patched")
        patches_applied += 1
    else:
        pat_b = rb'(\.\.\.[\w$]+\]\);)(const [\w$]+=[\w$]+\.get\("userThemeMode"\))'

        def repl_b(m):
            # Use raw string slicing (per Electron docs) — NOT new URL() parsing.
            # computer://home/path  → slice(11) → "home/path"  → "/home/path"
            # computer:///home/path → slice(11) → "/home/path" → "/home/path"
            handler = (
                b"Ae.app.whenReady().then(()=>{"
                b'Ae.session.defaultSession.protocol.handle("computer",async(e)=>{'
                b"let p=e.url.slice(11);"
                b'if(!p.startsWith("/"))p="/"+p;'
                b'return Ae.net.fetch("file://"+p)'
                b"})});"
            )
            return m.group(1) + handler + m.group(2)

        content, count = re.subn(pat_b, repl_b, content)
        if count > 0:
            print(f"  [OK] Part B (protocol handler): {count} match(es)")
            patches_applied += 1
        else:
            print("  [FAIL] Part B (protocol handler): 0 matches")

    # ── Part C: Convert computer:// in shell.openExternal ─────────────
    #
    # Fallback for links opened externally (not in-app preview).
    # Converts computer:// → file:// before calling xdg-open.
    #
    # Pattern: function <name>(<param>){<electron>.shell.openExternal(<param>)

    ext_marker = b'startsWith("computer://")'

    if ext_marker in content:
        print("  [OK] Part C (openExternal rewrite): already patched")
        patches_applied += 1
    else:
        pat_c = rb"(function [\w$]+\()([\w$]+)(\)\{)([\w$]+)(\.shell\.openExternal\()\2(\))"

        def repl_c(m):
            param = m.group(2).decode()
            # Replace computer:// (2 slashes) or computer:/// (3 slashes)
            # with file:/// — handles both URL variants correctly.
            # computer://home/path  → file:///home/path
            # computer:///home/path → file:///home/path
            inject = f'if({param}.startsWith("computer://")){{{param}={param}.replace(/^computer:\\/\\/\\/?/,"file:///")}}'
            return m.group(1) + m.group(2) + m.group(3) + inject.encode() + m.group(4) + m.group(5) + m.group(2) + m.group(6)

        content, count = re.subn(pat_c, repl_c, content)
        if count > 0:
            print(f"  [OK] Part C (openExternal rewrite): {count} match(es)")
            patches_applied += 1
        else:
            print("  [FAIL] Part C (openExternal rewrite): 0 matches")

    # ── Part D: Allow computer:// in PreviewContext.isAllowedUrl ────────
    #
    # The preview panel (WebContentsView for in-app file preview) only allows
    # localhost URLs. When the web app calls navigatePreview with a computer://
    # URL, isAllowedUrl rejects it → white page.
    #
    # We inject an early return for computer:// URLs, which our Part B protocol
    # handler will serve as local file content.
    #
    # Pattern: try{const <r>=new URL(<e>);return <lln>(<r>.hostname)&&<r>.port===
    # Inject before try: if(<e>.startsWith("computer://"))return!0;

    preview_marker = b'startsWith("computer://"))return!0;try'

    if preview_marker in content:
        print("  [OK] Part D (preview isAllowedUrl): already patched")
        patches_applied += 1
    else:
        pat_d = rb"(\.pathToFileURL\(this\.tempFilePath\)\.href\);)(try\{const )([\w$]+)(=new URL\()([\w$]+)(\);return [\w$]+\()\3(\.hostname\)&&)\3(\.port===)"

        def repl_d(m):
            param = m.group(5).decode()  # The URL parameter (e)
            inject = f'if({param}.startsWith("computer://"))return!0;'
            return m.group(1) + inject.encode() + m.group(2) + m.group(3) + m.group(4) + m.group(5) + m.group(6) + m.group(3) + m.group(7) + m.group(3) + m.group(8)

        content, count = re.subn(pat_d, repl_d, content)
        if count > 0:
            print(f"  [OK] Part D (preview isAllowedUrl): {count} match(es)")
            patches_applied += 1
        else:
            print("  [FAIL] Part D (preview isAllowedUrl): 0 matches")

    # ── Part E: IPC handler for renderer click interceptor ──────────────
    #
    # The renderer preload (fix_computer_url_renderer.py) sends
    # '__open_computer_url' IPC messages when computer:// links are clicked.
    # Register an ipcMain handler to open them via shell.openExternal.
    #
    # Inject after the whenReady protocol handler (Part B marker).

    ipc_marker = b"__open_computer_url"

    if ipc_marker in content:
        print("  [OK] Part E (IPC handler): already patched")
        patches_applied += 1
    else:
        # Inject right after our Part B whenReady block
        pat_e = rb'(protocol\.handle\("computer",async\(e\)\=>\{let p=e\.url\.slice\(11\);if\(!p\.startsWith\("/"\)\)p="/"\+p;return Ae\.net\.fetch\("file://"\+p\)\})\)\}\);'

        def repl_e(m):
            ipc_handler = (
                b'Ae.ipcMain.on("__open_computer_url",(ev,u)=>{'
                b'if(typeof u!=="string"||!u.startsWith("file:///"))return;'
                b"const w=new Ae.BrowserWindow({width:900,height:700,"
                b'title:u.split("/").pop()||"Preview",'
                b"webPreferences:{sandbox:!0}});"
                b'w.loadURL(u).catch(e=>T.error("[computer-url] load failed",e))'
                b"});"
            )
            return m.group(0) + ipc_handler

        content, count = re.subn(pat_e, repl_e, content)
        if count > 0:
            print(f"  [OK] Part E (IPC handler): {count} match(es)")
            patches_applied += 1
        else:
            print("  [FAIL] Part E (IPC handler): 0 matches")

    # ── Final check ───────────────────────────────────────────────────

    if patches_applied < EXPECTED_PATCHES:
        print(f"  [FAIL] Only {patches_applied}/{EXPECTED_PATCHES} patches applied")
        return False

    if content != original_content:
        with open(filepath, "wb") as f:
            f.write(content)
        print(f"  [PASS] All {patches_applied} patches applied")
    else:
        print("  [PASS] No changes needed (already patched)")

    return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_computer_url(sys.argv[1])
    sys.exit(0 if success else 1)
