#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Patch Claude Desktop to use system-installed Claude Code on Linux.

The official Claude Desktop app only supports downloading Claude Code for
macOS and Windows. This patch modifies the app to detect and use a
system-installed Claude Code binary on Linux, checking multiple known
install locations (/usr/bin, ~/.local/bin, /usr/local/bin).

Usage: python3 fix_claude_code.py <path_to_index.js>
"""

import sys
import os
import re


def patch_claude_code(filepath):
    """Patch the Claude Code downloader to use system binary on Linux."""

    print(f"=== Patch: fix_claude_code ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content
    failed = False

    # Patch 1: getHostPlatform() - Add Linux support
    # This is the root cause - it throws "Unsupported platform" for Linux
    # Use flexible regex to capture the arch variable name dynamically
    # The win32 block may be hardcoded ("win32-x64") or conditional (arch==="arm64"?...)
    platform_pattern = rb'(getHostPlatform\(\)\{const (\w+)=process\.arch;if\(process\.platform==="darwin"\)return \2==="arm64"\?"darwin-arm64":"darwin-x64";if\(process\.platform==="win32"\)return)(.+?)(;throw new Error\()'

    def platform_replacement(m):
        arch_var = m.group(2)
        win32_return = m.group(3)
        linux_check = (b'if(process.platform==="linux")return ' + arch_var +
                       b'==="arm64"?"linux-arm64":"linux-x64";')
        return m.group(1) + win32_return + b';' + linux_check + b'throw new Error('

    content, count1 = re.subn(platform_pattern, platform_replacement, content)
    if count1 >= 1:
        print(f"  [OK] getHostPlatform(): {count1} match(es)")
    elif b'getHostPlatform(){' in content and b'if(process.platform==="linux")return' in content and b'"linux-x64"' in content:
        # More specific "already patched" check — require linux-x64 near getHostPlatform
        print(f"  [OK] getHostPlatform(): already patched")
    else:
        print(f"  [FAIL] getHostPlatform(): 0 matches, expected >= 1")
        failed = True

    # Patch 2: getBinaryPathIfReady() - Find claude binary on Linux
    # IMPORTANT: Check Linux BEFORE calling getHostTarget() for safety
    # Match only the function signature and inject Linux check right after {
    # Negative lookahead ensures idempotency (won't re-patch if already applied)
    # Checks known paths first, then falls back to `which claude` for dynamic
    # resolution (handles npm global, nvm, etc.).
    binary_pattern = rb'(async getBinaryPathIfReady\(\)\{)(?!if\(process\.platform==="linux"\))'

    linux_binary_check = (b'if(process.platform==="linux"){try{const fs=require("fs");'
                          b'for(const p of["/usr/bin/claude",'
                          b'(process.env.HOME||"")+"/.local/bin/claude",'
                          b'"/usr/local/bin/claude"])'
                          b'if(fs.existsSync(p))return p;'
                          b'return require("child_process").execSync("which claude",{encoding:"utf-8"}).trim()}'
                          b'catch(err){}}')

    def binary_replacement(m):
        return m.group(1) + linux_binary_check

    content, count2 = re.subn(binary_pattern, binary_replacement, content, count=1)
    if count2 >= 1:
        print(f"  [OK] getBinaryPathIfReady(): {count2} match(es)")
    elif b'async getBinaryPathIfReady(){if(process.platform==="linux")' in content:
        print(f"  [OK] getBinaryPathIfReady(): already patched")
    else:
        print(f"  [FAIL] getBinaryPathIfReady(): 0 matches, expected >= 1")
        failed = True

    # Patch 3: getStatus() - Return Ready if system binary exists on Linux
    # IMPORTANT: Check Linux BEFORE calling getHostTarget() for safety
    # Use regex to capture the enum name (Yo, tc, etc.) dynamically
    status_pattern = rb'async getStatus\(\)\{if\(await this\.getLocalBinaryPath\(\)\)return ([\w$]+)\.Ready;const (\w+)=this\.getHostTarget\(\);if\(this\.preparingPromise\)return \1\.Updating;if\(await this\.binaryExistsForTarget\(\2,this\.requiredVersion\)\)'

    def status_replacement(m):
        enum_name = m.group(1)  # Capture the enum name (ps, etc.)
        var_name = m.group(2)   # Capture the variable name (r, etc.)
        return (b'async getStatus(){if(process.platform==="linux"){try{const fs=require("fs");'
                b'for(const p of["/usr/bin/claude",(process.env.HOME||"")+"/.local/bin/claude","/usr/local/bin/claude"])'
                b'if(fs.existsSync(p))return ' + enum_name + b'.Ready;'
                b'try{require("child_process").execSync("which claude",{encoding:"utf-8"});return ' + enum_name + b'.Ready}catch(e2){}'
                b'return ' + enum_name + b'.NotInstalled}catch(err){return ' + enum_name +
                b'.NotInstalled}}if(await this.getLocalBinaryPath())return ' + enum_name + b'.Ready;const ' +
                var_name + b'=this.getHostTarget();if(this.preparingPromise)return ' + enum_name +
                b'.Updating;if(await this.binaryExistsForTarget(' + var_name + b',this.requiredVersion))')

    content, count3 = re.subn(status_pattern, status_replacement, content)
    if count3 >= 1:
        print(f"  [OK] getStatus(): {count3} match(es)")
    elif b'async getStatus(){if(process.platform==="linux")' in content:
        print(f"  [OK] getStatus(): already patched")
    else:
        print(f"  [FAIL] getStatus(): 0 matches, expected >= 1")
        failed = True

    # Check results
    if failed:
        print("  [FAIL] Some patterns did not match")
        return False

    # Write back if changed
    if content != original_content:
        with open(filepath, 'wb') as f:
            f.write(content)
        print("  [PASS] All patterns matched and applied")
        return True
    else:
        print("  [WARN] No changes made (patterns may have already been applied)")
        return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_claude_code(sys.argv[1])
    sys.exit(0 if success else 1)
