#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Enable Code and Cowork features on Linux.

Four-part patch:
1. Individual function patch: Remove platform!=="darwin" gate from both
   chillingSlothFeat and quietPenguin functions in Oh() (static layer).
   Cowork tab is functional when claude-cowork-service daemon is running.
   VM operations go through the TypeScript VM client (patched by fix_cowork_linux.py).
2. chillingSlothLocal: No Linux gate needed — naturally returns
   {status:"supported"} on Linux (only gates Windows ARM64).
3. mC() merger patch: Override features at the async merger layer.
   Enables quietPenguin/louderPenguin (Code tab, bypasses QL gate),
   chillingSlothFeat/chillingSlothLocal/yukonSilver/yukonSilverGems (Cowork),
   and ccdPlugins (Plugin UI) with {status:"supported"}.
4. Preferences defaults patch: Change louderPenguinEnabled and
   quietPenguinEnabled defaults from false to true so the renderer
   (claude.ai web content) enables the Code tab UI.

The mC() patch makes features "supported" (capability), but the renderer
also checks the "Enabled" preference (user setting). Both must be true
for the Code tab to appear.

Usage: python3 enable_local_agent_mode.py <path_to_index.js>
"""

import sys
import os
import re


def patch_local_agent_mode(filepath):
    """Enable Code features (quietPenguin/louderPenguin) on Linux by patching platform-gated functions."""

    print(f"=== Patch: enable_local_agent_mode ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content
    failed = False

    # Patch 1: Remove platform!=="darwin" gate from both chillingSlothFeat and quietPenguin
    # Original: function XXX(){return process.platform!=="darwin"?{status:"unavailable"}:{status:"supported"}}
    # Changed:  function XXX(){return{status:"supported"}}
    #
    # Two functions match this pattern:
    #   matches[0] = chillingSlothFeat (e.g. agt) — PATCH (Cowork tab, needs daemon)
    #   matches[1] = quietPenguin (e.g. ogt) — PATCH
    #
    # Use flexible pattern with \w+ to match any minified function name
    pattern1 = rb'(function )(\w+)(\(\)\{return )process\.platform!=="darwin"\?\{status:"unavailable"\}:(\{status:"supported"\}\})'

    matches = list(re.finditer(pattern1, content))
    if len(matches) >= 2:
        # Patch both: reverse order to preserve byte offsets
        for m in reversed(matches):
            replacement = m.group(1) + m.group(2) + m.group(3) + m.group(4)
            content = content[:m.start()] + replacement + content[m.end():]
        print(f"  [OK] chillingSlothFeat ({matches[0].group(2).decode()}) + quietPenguin ({matches[1].group(2).decode()}): both patched")
    elif len(matches) == 1:
        m = matches[0]
        replacement = m.group(1) + m.group(2) + m.group(3) + m.group(4)
        content = content[:m.start()] + replacement + content[m.end():]
        print(f"  [OK] darwin-gated function ({matches[0].group(2).decode()}): 1 match")
    else:
        print(f"  [FAIL] darwin-gated functions: 0 matches, expected at least 1")
        failed = True

    # Check results
    if failed:
        print("  [FAIL] Required patterns did not match")
        return False

    # Patch 1b: Bypass yukonSilver (NH) platform gate on Linux
    # NH()/WOt() gates yukonSilver on darwin/win32 only. On Linux it returns
    # {status:"unsupported"} which prevents Cowork from appearing.
    # We inject an early return for Linux so the TypeScript VM client
    # can talk to the cowork-svc-linux daemon.
    #
    # Two format variants exist across versions:
    #   Old (≤v1.1.4088): reason:`Unsupported platform: ${t}` (template literal)
    #   New (≥v1.1.4173): reason:Ue.formatMessage({defaultMessage:"Cowork is not
    #     currently supported on {platform}",id:"YXG53SzpKR"},{platform:ak()}),
    #     unsupportedCode:"unsupported_platform"
    #   The formatMessage 'id' field was added in v1.1.4328; the regex uses an
    #   optional group (?:,id:"[^"]*")? to handle both variants.
    nh_pattern_old = rb'(function \w+\(\)\{)(const (\w+)=process\.platform;if\(\3!=="darwin"&&\3!=="win32"\)return\{status:"unsupported",reason:`Unsupported platform: \$\{\3\}`\})'
    nh_pattern_new = rb'(function \w+\(\)\{)(const (\w+)=process\.platform;if\(\3!=="darwin"&&\3!=="win32"\)return\{status:"unsupported",reason:\w+\.formatMessage\(\{defaultMessage:"Cowork is not currently supported on \{platform\}"(?:,id:"[^"]*")?\},\{platform:\w+\(\)\}\),unsupportedCode:"unsupported_platform"\};)'

    def nh_replacement(m):
        return m.group(1) + b'if(process.platform==="linux")return{status:"supported"};' + m.group(2)

    content, count1b = re.subn(nh_pattern_old, nh_replacement, content, count=1)
    if count1b >= 1:
        print(f"  [OK] yukonSilver (NH): Linux early return injected ({count1b} match)")
    elif b'if(process.platform==="linux")return{status:"supported"};const' in content:
        print(f"  [OK] yukonSilver (NH): already patched")
    else:
        content, count1b = re.subn(nh_pattern_new, nh_replacement, content, count=1)
        if count1b >= 1:
            print(f"  [OK] yukonSilver (NH): Linux early return injected (formatMessage variant, {count1b} match)")
        else:
            print(f"  [WARN] yukonSilver (NH): 0 matches")

    # Patch 2: chillingSlothLocal — no Linux gate needed
    # This function only gates Windows ARM64, returning {status:"supported"} on Linux
    # naturally. No additional patching needed.
    print(f"  [OK] chillingSlothLocal: no gate needed (naturally returns supported on Linux)")

    # Patch 3: Override features in mC() async merger
    # The mC() function merges Oh() with async overrides. Features wrapped by QL()
    # in Oh() are blocked in production. We append overrides after the last async
    # property so they take precedence over the ...Oh() spread.
    #
    # We override:
    # - quietPenguin/louderPenguin → "supported" (Code tab, bypasses QL gate)
    # - chillingSlothFeat/chillingSlothLocal → "supported" (Cowork tab, needs daemon)
    # - yukonSilver/yukonSilverGems → "supported" (VM features, needs daemon)
    # - ccdPlugins → "supported" (Plugin UI, defensive override for future gating)
    #
    # The async merger spreads ...dg() and then overrides some features with async versions.
    # The last property changes between versions. We match any feature:await pattern before })
    # Before: louderPenguin:await fwt()})  [v1.1.2685]
    # After:  louderPenguin:await fwt(),quietPenguin:{status:"supported"},...})
    pattern3 = rb'(const \w+=async\(\)=>\(\{\.\.\.[\w$]+\(\),[^}]+)(await [\w$]+\(\))\}\)'
    replacement3 = rb'\1\2,quietPenguin:{status:"supported"},louderPenguin:{status:"supported"},chillingSlothFeat:{status:"supported"},chillingSlothLocal:{status:"supported"},yukonSilver:{status:"supported"},yukonSilverGems:{status:"supported"},ccdPlugins:{status:"supported"}})'

    content, count3 = re.subn(pattern3, replacement3, content)
    if count3 >= 1:
        print(f"  [OK] mC() feature merger: 7 features overridden ({count3} match)")
    else:
        print(f"  [FAIL] mC() feature merger: 0 matches, expected 1")
        failed = True

    # Check results
    if failed:
        print("  [FAIL] Required patterns did not match")
        return False

    # Patch 4: Change preferences defaults for Code features
    # The renderer (claude.ai web content) checks louderPenguinEnabled and
    # quietPenguinEnabled preferences to show the Code tab. The defaults are
    # false (disabled). We change them to true so the Code tab appears.
    # Feature name strings are stable IPC identifiers (not minified).
    pattern3a = rb'quietPenguinEnabled:!1,louderPenguinEnabled:!1'
    replacement3a = rb'quietPenguinEnabled:!0,louderPenguinEnabled:!0'
    content, count3a = re.subn(pattern3a, replacement3a, content)
    if count3a >= 1:
        print(f"  [OK] Preferences defaults: quietPenguinEnabled + louderPenguinEnabled → true ({count3a} match)")
    else:
        print(f"  [FAIL] Preferences defaults: 0 matches for quietPenguinEnabled/louderPenguinEnabled")
        failed = True

    # Check results
    if failed:
        print("  [FAIL] Required patterns did not match")
        return False

    # Patch 5: Spoof platform as "darwin" in HTTP headers
    # The claude.ai server checks the anthropic-client-os-platform header to decide
    # whether to send Cowork tab data. Cowork is "a research preview on macOS" per
    # the admin page. We spoof the platform variable used in the header setup.
    # Pattern: e=Ma.platform,r=Ma.getSystemVersion();Ae.session...onBeforeSendHeaders
    # We replace: e=Ma.platform → e=process.platform==="linux"?"darwin":Ma.platform
    header_pattern = rb'(const \w+=\w+\.app\.getVersion\(\),)(\w+)(=)(\w+)(\.platform,)(\w+)(=\4\.getSystemVersion\(\);)'

    def header_replacement(m):
        plat_var = m.group(2)  # e
        os_mod = m.group(4)    # Ma
        ver_var = m.group(6)   # r
        return (m.group(1) + plat_var + m.group(3) +
                b'process.platform==="linux"?"darwin":' + os_mod + m.group(5) +
                ver_var + m.group(7))

    content, count5 = re.subn(header_pattern, header_replacement, content)
    if count5 >= 1:
        print(f"  [OK] HTTP header platform spoof: {count5} match(es)")
    else:
        print(f"  [WARN] HTTP header platform spoof: 0 matches")

    # Patch 5b: Spoof User-Agent header to claim macOS
    # The User-Agent string contains "Linux" which the server uses for platform
    # detection. Replace "X11; Linux ..." → "Macintosh; Intel Mac OS X 10_15_7" in the UA.
    # Pattern: let l=o;s.set("user-agent",l)  (the existing no-op UA passthrough)
    # The variable before .set() changes between versions (s, a, etc.)
    ua_pattern2 = rb'(let )(\w+)(=)(\w+)(;)(\w+\.set\("user-agent",)\2(\))'

    def ua_replacement2(m):
        var = m.group(2)   # l
        orig = m.group(4)  # o
        return (m.group(1) + var + m.group(3) + orig + m.group(5) +
                b'if(process.platform==="linux"){' + var +
                b'=' + var + b'.replace(/X11; Linux [^)]+/g,"Macintosh; Intel Mac OS X 10_15_7")}' +
                m.group(6) + var + m.group(7))

    content, count5b = re.subn(ua_pattern2, ua_replacement2, content)
    if count5b >= 1:
        print(f"  [OK] User-Agent header spoof: {count5b} match(es)")
    else:
        print(f"  [WARN] User-Agent header spoof: 0 matches")

    # Patch 6: Spoof platform in getSystemInfo IPC response
    # The renderer calls getSystemInfo() and checks platform. We report "win32"
    # on Linux so the renderer shows Ctrl/Alt keyboard shortcuts (not macOS ⌘/⌥).
    # Server-facing spoofs (HTTP headers) remain "darwin" for Cowork compatibility.
    sysinfo_pattern = rb'(platform:)process\.platform(,arch:process\.arch,total_memory:[\w$]+\.totalmem\(\))'

    sysinfo_replacement = rb'\1(process.platform==="linux"?"win32":process.platform)\2'

    content, count6 = re.subn(sysinfo_pattern, sysinfo_replacement, content)
    if count6 >= 1:
        print(f"  [OK] getSystemInfo platform spoof: {count6} match(es)")
    else:
        print(f"  [WARN] getSystemInfo platform spoof: 0 matches")

    # Write back if changed
    if content != original_content:
        with open(filepath, 'wb') as f:
            f.write(content)
        print("  [PASS] Code + Cowork features enabled in index.js")
    else:
        print("  [WARN] No changes made to index.js (patterns may have already been applied)")

    # Patch 7: Spoof window.process.platform in mainView.js preload
    # The preload script exposes a filtered process object to the renderer via
    # contextBridge.exposeInMainWorld("process", Oe). The renderer (claude.ai web
    # app) checks window.process.platform for UI decisions like keyboard shortcuts.
    # We report "win32" so the renderer shows Ctrl/Alt shortcuts (not macOS ⌘/⌥).
    mainview_path = os.path.join(os.path.dirname(filepath), 'mainView.js')
    if os.path.exists(mainview_path):
        with open(mainview_path, 'rb') as f:
            mv_content = f.read()
        mv_original = mv_content

        # Pattern: ...Object.fromEntries(Object.entries(process).filter(([e])=>Na[e]));Oe.version=Ia().appVersion;
        # We inject: if(process.platform==="linux"){Oe.platform="win32"} after .appVersion;
        mv_pattern = rb'(Object\.fromEntries\(Object\.entries\(process\)\.filter\(\(\[\w+\]\)=>\w+\[\w+\]\)\);)(\w+)(\.version=\w+\(\)\.appVersion;)'

        def mv_replacement(m):
            proc_var = m.group(2)
            return (m.group(1) + proc_var + m.group(3) +
                    b'if(process.platform==="linux"){' + proc_var + b'.platform="win32"}')

        mv_content, mv_count = re.subn(mv_pattern, mv_replacement, mv_content, count=1)
        if mv_count >= 1:
            print(f"  [OK] mainView.js: window.process.platform spoof ({mv_count} match)")
        elif b'.platform="win32"' in mv_content or b'.platform="darwin"' in mv_content:
            print(f"  [OK] mainView.js: window.process.platform spoof already applied")
        else:
            print(f"  [WARN] mainView.js: window.process.platform spoof: 0 matches")

        if mv_content != mv_original:
            with open(mainview_path, 'wb') as f:
                f.write(mv_content)
            print("  [PASS] mainView.js patched successfully")
    else:
        print(f"  [WARN] mainView.js not found at {mainview_path}")

    return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_local_agent_mode(sys.argv[1])
    sys.exit(0 if success else 1)
