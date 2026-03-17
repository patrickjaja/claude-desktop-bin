#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Register stub IPC handlers for CoworkSpaces on Linux.

On macOS/Windows, the CoworkSpaces eipc handlers are registered by the native
Cowork backend during session manager initialization. On Linux, this doesn't
happen because the native backend is not loaded, causing repeated errors:

  Error: No handler registered for '..._CoworkSpaces_$_getAllSpaces'

This patch registers stub handlers that return sensible defaults so the
renderer doesn't error when querying spaces at startup. When the
claude-cowork-service daemon IS running, the real spaces service should
eventually initialize and replace these stubs.

Stubs return:
- getAllSpaces: empty array
- getSpace: null
- createSpace/updateSpace/deleteSpace: null (no-op)
- addFolderToSpace/removeFolderFromSpace: null (no-op)
- addProjectToSpace/removeProjectFromSpace: null (no-op)
- addLinkToSpace/removeLinkFromSpace: null (no-op)
- getAutoMemoryDir: null
- listFolderContents: empty array
- readFileContents: null
- openFile: null (no-op)
- createSpaceFolder: null (no-op)
- copyFilesToSpaceFolder: null (no-op)

Usage: python3 fix_cowork_spaces.py <path_to_index.js>
"""

import sys
import os
import re


def build_stub_handlers_js(eipc_prefix):
    """Build the stub handler JS code with the given eipc prefix."""
    # Methods that use ipcRenderer.invoke() (need ipcMain.handle())
    invoke_methods = {
        'getAllSpaces': '[]',
        'getSpace': 'null',
        'createSpace': 'null',
        'updateSpace': 'null',
        'deleteSpace': 'null',
        'addFolderToSpace': 'null',
        'removeFolderFromSpace': 'null',
        'addProjectToSpace': 'null',
        'removeProjectFromSpace': 'null',
        'addLinkToSpace': 'null',
        'removeLinkFromSpace': 'null',
        'getAutoMemoryDir': 'null',
        'listFolderContents': '[]',
        'readFileContents': 'null',
        'openFile': 'null',
        'createSpaceFolder': 'null',
        'copyFilesToSpaceFolder': 'null',
    }

    handlers = []
    for method, default in invoke_methods.items():
        handlers.append(f'_ipc.handle(_P+"{method}",()=>{default});')

    return (
        'if(process.platform==="linux"){'
        'const _ipc=require("electron").ipcMain;'
        f'const _P="{eipc_prefix}";'
        + ''.join(handlers) +
        '}'
    )


def extract_eipc_uuid(content):
    """Extract the eipc UUID from the file content dynamically."""
    m = re.search(rb'\$eipc_message\$_([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})', content)
    if m:
        return m.group(1).decode('utf-8')
    return None


def patch_cowork_spaces(filepath):
    """Register CoworkSpaces stub IPC handlers on Linux."""

    print(f"=== Patch: fix_cowork_spaces ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content

    # Check if CoworkSpaces handlers already exist in the main process
    if b'CoworkSpaces' in content:
        print(f"  [OK] CoworkSpaces handlers already registered upstream")
        print("  [PASS] No patch needed")
        return True

    # Dynamically extract the eipc UUID from the file
    uuid = extract_eipc_uuid(content)
    if not uuid:
        mainview = os.path.join(os.path.dirname(filepath), 'mainView.js')
        if os.path.exists(mainview):
            with open(mainview, 'rb') as f:
                uuid = extract_eipc_uuid(f.read())
    if not uuid:
        print(f"  [FAIL] Could not extract eipc UUID from source files")
        return False

    eipc_prefix = f"$eipc_message$_{uuid}_$_claude.web_$_CoworkSpaces_$_"
    print(f"  [OK] Extracted eipc UUID: {uuid}")

    stub_js = build_stub_handlers_js(eipc_prefix)

    # Inject after app.on("ready", async () => {
    pattern = rb'(app\.on\("ready",async\(\)=>\{)'

    replacement = rb'\1' + stub_js.encode('utf-8')

    content, count = re.subn(pattern, replacement, content, count=1)
    if count >= 1:
        print(f"  [OK] CoworkSpaces stub handlers: injected ({count} match)")
    else:
        print(f"  [FAIL] app.on(\"ready\") pattern: 0 matches")
        return False

    if content != original_content:
        with open(filepath, 'wb') as f:
            f.write(content)
        print("  [PASS] CoworkSpaces handlers registered for Linux")
        return True
    else:
        print("  [WARN] No changes made")
        return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_cowork_spaces(sys.argv[1])
    sys.exit(0 if success else 1)
