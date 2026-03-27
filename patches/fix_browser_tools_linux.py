#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Enable Chrome browser tools ("Claude in Chrome") on Linux.

Claude Desktop's "Claude in Chrome" MCP server provides 18 browser automation tools
(navigate, read_page, javascript_tool, computer, etc.) via a Chrome extension. The
feature requires a native messaging host binary to bridge Chrome <-> Claude Desktop.

On Windows/macOS, Anthropic ships a proprietary Rust binary (chrome-native-host).
On Linux, we leverage Claude Code's existing native host wrapper at
~/.claude/chrome/chrome-native-host, which implements the identical 4-byte
length-prefixed JSON protocol over stdio and creates Unix domain sockets for
MCP communication.

Two-part patch (A-B):

A. Binary path resolution.
   e$t() resolves the chrome-native-host binary path. The non-darwin packaged
   branch returns <appPath>/locales/chrome-native-host which doesn't exist on
   Linux. We inject a Linux-specific branch that returns Claude Code's native
   host at ~/.claude/chrome/chrome-native-host.

B. NativeMessagingHosts directory paths.
   t$t() returns browser-specific manifest directories. On Linux it returns []
   (empty), so no manifests are installed and Chrome can't find the native host.
   We add Linux browser paths (Chrome, Chromium, Brave, Edge, Vivaldi, Opera).

Requires: Claude Code CLI installed (provides ~/.claude/chrome/chrome-native-host)

Usage: python3 fix_browser_tools_linux.py <path_to_index.js>
"""

import sys
import os
import re


def patch_browser_tools_linux(filepath):
    """Enable Chrome browser tools on Linux."""

    print(f"=== Patch: fix_browser_tools_linux ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content
    patches_applied = 0

    # ── Patch A: Binary path resolution ────────────────────────────────
    #
    # Original (minified, variable names change per release):
    #   function e$t(){
    #     const t=process.platform==="win32"?`${xY}.exe`:xY;
    #     if(ke.app.isPackaged)
    #       if(process.platform==="darwin"){
    #         const e=ke.app.getPath("exe"),r=Ae.dirname(Ae.dirname(e));
    #         return Ae.join(r,"Helpers",t)
    #       }else return Ae.join((...),t);
    #     else return Ae.join(ke.app.getAppPath(),...,t)
    #   }
    #
    # The }else return after the darwin block falls through to a Windows/generic
    # path that doesn't exist on Linux. We insert a Linux check before it.
    #
    # Injection point: between "Helpers",VAR)} and else return VAR.join(
    # We add: else if(process.platform==="linux")return require("path").join(
    #           require("os").homedir(),".claude","chrome","chrome-native-host");

    pattern_a = rb'"Helpers",\w+\)}else return \w+\.join\('

    linux_binary = (
        b'"linux")return require("path").join('
        b'require("os").homedir(),".claude","chrome","chrome-native-host");'
    )

    already_a = rb'process\.platform==="linux"\)return require\("path"\)\.join\(require\("os"\)\.homedir\(\),".claude"'

    if re.search(already_a, content):
        print(f"  [OK] Binary path resolution: already patched (skipped)")
        patches_applied += 1
    else:
        def replacement_a(m):
            matched = m.group(0)
            return matched.replace(
                b'}else return',
                b'}else if(process.platform===' + linux_binary + b'else return',
            )

        content, count_a = re.subn(pattern_a, replacement_a, content, count=1)
        if count_a >= 1:
            print(f"  [OK] Binary path resolution: redirected to Claude Code native host ({count_a} match)")
            patches_applied += 1
        else:
            print(f"  [FAIL] Binary path resolution: pattern not found")
            print(f"         Debug: rg -o '\"Helpers\".{{0,50}}' index.js")

    # ── Patch B: NativeMessagingHosts directory paths ───────────────────
    #
    # Original:
    #   function t$t(){
    #     const t=os.homedir();
    #     if(process.platform==="darwin"){...return [...]}
    #     return process.platform==="win32"
    #       ? [{name:"All",path:Ae.join(ke.app.getPath("userData"),"ChromeNativeHost")}]
    #       : []
    #   }
    #
    # The trailing :[] is the Linux case. We replace it with a ternary that
    # returns Linux browser NativeMessagingHosts paths via an IIFE.

    pattern_b = rb'("ChromeNativeHost"\)\}\]):\[\]'

    linux_paths = (
        b':process.platform==="linux"?(()=>{'
        b'const h=require("os").homedir(),p=require("path");'
        b'return['
        b'{name:"Chrome",path:p.join(h,".config","google-chrome","NativeMessagingHosts")},'
        b'{name:"Chromium",path:p.join(h,".config","chromium","NativeMessagingHosts")},'
        b'{name:"Brave",path:p.join(h,".config","BraveSoftware","Brave-Browser","NativeMessagingHosts")},'
        b'{name:"Edge",path:p.join(h,".config","microsoft-edge","NativeMessagingHosts")},'
        b'{name:"Vivaldi",path:p.join(h,".config","vivaldi","NativeMessagingHosts")},'
        b'{name:"Opera",path:p.join(h,".config","opera","NativeMessagingHosts")}'
        b']})():[]'
    )

    already_b = rb'"ChromeNativeHost"\)\}\]:process\.platform==="linux"'

    if re.search(already_b, content):
        print(f"  [OK] NativeMessagingHosts paths: already patched (skipped)")
        patches_applied += 1
    else:
        content, count_b = re.subn(
            pattern_b,
            lambda m: m.group(1) + linux_paths,
            content,
            count=1,
        )
        if count_b >= 1:
            print(f"  [OK] NativeMessagingHosts paths: added 6 Linux browsers ({count_b} match)")
            patches_applied += 1
        else:
            print(f"  [FAIL] NativeMessagingHosts paths: pattern not found")
            print(f"         Debug: rg -o '\"ChromeNativeHost\".{{0,30}}' index.js")

    # ── Results ────────────────────────────────────────────────────────

    if patches_applied == 0:
        print("  [FAIL] No patches could be applied")
        return False

    if content == original_content:
        print("  [WARN] No changes made (patterns may have already been applied)")
        return True

    # Verify patches didn't introduce a brace imbalance
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

    success = patch_browser_tools_linux(sys.argv[1])
    sys.exit(0 if success else 1)
