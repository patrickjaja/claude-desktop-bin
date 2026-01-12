#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Patch Claude Desktop to use system-installed Claude Code on Linux.

The official Claude Desktop app only supports downloading Claude Code for
macOS and Windows. This patch modifies the app to detect and use a
system-installed Claude Code binary (/usr/bin/claude) on Linux.

Usage: python3 fix_claude_code.py <path_to_index.js>
"""

import sys
import os


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
    old_platform = b'getHostPlatform(){const e=process.arch;if(process.platform==="darwin")return e==="arm64"?"darwin-arm64":"darwin-x64";if(process.platform==="win32")return"win32-x64";throw new Error(`Unsupported platform: ${process.platform}-${e}`)}'
    new_platform = b'getHostPlatform(){const e=process.arch;if(process.platform==="darwin")return e==="arm64"?"darwin-arm64":"darwin-x64";if(process.platform==="win32")return"win32-x64";if(process.platform==="linux")return e==="arm64"?"linux-arm64":"linux-x64";throw new Error(`Unsupported platform: ${process.platform}-${e}`)}'

    count1 = content.count(old_platform)
    if count1 >= 1:
        content = content.replace(old_platform, new_platform)
        print(f"  [OK] getHostPlatform(): {count1} match(es)")
    else:
        print(f"  [FAIL] getHostPlatform(): 0 matches, expected >= 1")
        failed = True

    # Patch 2: getBinaryPathIfReady() - Check /usr/bin/claude first on Linux
    # IMPORTANT: Check Linux BEFORE calling getHostTarget() for safety
    old_binary_ready = b'async getBinaryPathIfReady(){const e=this.getHostTarget();return await this.binaryExistsForTarget(e,this.requiredVersion)?this.getBinaryPathForTarget(e,this.requiredVersion):null}'
    new_binary_ready = b'async getBinaryPathIfReady(){if(process.platform==="linux"){try{const fs=require("fs");if(fs.existsSync("/usr/bin/claude"))return"/usr/bin/claude"}catch(err){}}const e=this.getHostTarget();return await this.binaryExistsForTarget(e,this.requiredVersion)?this.getBinaryPathForTarget(e,this.requiredVersion):null}'

    count2 = content.count(old_binary_ready)
    if count2 >= 1:
        content = content.replace(old_binary_ready, new_binary_ready)
        print(f"  [OK] getBinaryPathIfReady(): {count2} match(es)")
    else:
        print(f"  [FAIL] getBinaryPathIfReady(): 0 matches, expected >= 1")
        failed = True

    # Patch 3: getStatus() - Return Ready if system binary exists on Linux
    # IMPORTANT: Check Linux BEFORE calling getHostTarget() for safety
    old_status = b'async getStatus(){const e=this.getHostTarget();if(this.preparingPromise)return Yo.Updating;if(await this.binaryExistsForTarget(e,this.requiredVersion))'
    new_status = b'async getStatus(){if(process.platform==="linux"){try{const fs=require("fs");if(fs.existsSync("/usr/bin/claude")){return Yo.Ready}return Yo.NotInstalled}catch(err){return Yo.NotInstalled}}const e=this.getHostTarget();if(this.preparingPromise)return Yo.Updating;if(await this.binaryExistsForTarget(e,this.requiredVersion))'

    count3 = content.count(old_status)
    if count3 >= 1:
        content = content.replace(old_status, new_status)
        print(f"  [OK] getStatus(): {count3} match(es)")
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
