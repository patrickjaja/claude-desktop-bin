#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Hide the Cowork tab on Linux.

The Cowork feature requires ClaudeVM which is not available on Linux.
The tab visibility is controlled server-side by the claude.ai web app,
so desktop feature flags alone cannot hide it. This patch injects
JavaScript into the main webContents on dom-ready that uses a
MutationObserver to hide any button/link with "Cowork" text.

Usage: python3 fix_hide_cowork_tab.py <path_to_index.js>
"""

import sys
import os
import re


def patch_hide_cowork_tab(filepath):
    """Hide Cowork tab on Linux by injecting JS on dom-ready."""

    print(f"=== Patch: fix_hide_cowork_tab ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content
    failed = False

    # Patch: Inject JS on dom-ready to hide the Cowork tab button
    #
    # The main webContents has a dom-ready handler:
    #   r.webContents.on("dom-ready",()=>{xg()})
    #
    # We add executeJavaScript that uses a MutationObserver to find and
    # hide any button/link with "Cowork" text. Uses single-quoted JS
    # string with double quotes inside to avoid escaping issues.
    pattern = rb'(\.webContents\.on\("dom-ready",\(\)=>\{)(xg\(\))\}'

    # Build the JS to inject. Single-quoted outer string, double quotes inside.
    # The script:
    # 1. Defines a hide function that finds buttons/links with "Cowork" text
    # 2. Runs it immediately
    # 3. Sets up a MutationObserver to catch dynamically rendered content
    # JS body uses double quotes inside. The outer wrapper in executeJavaScript
    # uses single quotes: executeJavaScript('...body...')
    # So double quotes inside the body are safe, but single quotes must be avoided.
    js_body = (
        b'(function(){'
        b'var h=function(){'
        b'document.querySelectorAll("button,a").forEach(function(b){'
        b'if(b.textContent.trim()==="Cowork"&&!b.__coworkDisabled){b.__coworkDisabled=true;b.disabled=true;b.style.opacity="0.4";b.style.cursor="default";b.addEventListener("click",function(e){e.preventDefault();e.stopImmediatePropagation()},true)}'
        b'})'
        b'};'
        b'h();'
        b'new MutationObserver(h).observe(document.body,{childList:true,subtree:true})'
        b'})()'
    )

    inject = (
        b"if(process.platform===\"linux\"){"
        b"r.webContents.executeJavaScript('"
        + js_body +
        b"').catch(function(){})}"
    )

    def replacement(m):
        return m.group(1) + m.group(2) + b';' + inject + b'}'

    content, count = re.subn(pattern, replacement, content, count=1)
    if count >= 1:
        print(f"  [OK] Cowork tab hide injection: {count} match(es)")
    else:
        print(f"  [FAIL] dom-ready handler: 0 matches")
        failed = True

    if failed:
        print("  [FAIL] Required patterns did not match")
        return False

    # Write back if changed
    if content != original_content:
        with open(filepath, 'wb') as f:
            f.write(content)
        print("  [PASS] Cowork tab hidden on Linux")
        return True
    else:
        print("  [WARN] No changes made (pattern may have already been applied)")
        return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_hide_cowork_tab(sys.argv[1])
    sys.exit(0 if success else 1)
