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

    # Patch 1: getBinaryPathIfReady() - Check /usr/bin/claude first on Linux
    old_binary_ready = b'async getBinaryPathIfReady(){return await this.binaryExists(this.requiredVersion)?this.getBinaryPath(this.requiredVersion):null}'
    new_binary_ready = b'async getBinaryPathIfReady(){console.log("[ClaudeCode] getBinaryPathIfReady called, platform:",process.platform);if(process.platform==="linux"){try{const fs=require("fs");const exists=fs.existsSync("/usr/bin/claude");console.log("[ClaudeCode] /usr/bin/claude exists:",exists);if(exists)return"/usr/bin/claude"}catch(e){console.log("[ClaudeCode] error checking /usr/bin/claude:",e)}}return await this.binaryExists(this.requiredVersion)?this.getBinaryPath(this.requiredVersion):null}'

    count1 = content.count(old_binary_ready)
    if count1 >= 1:
        content = content.replace(old_binary_ready, new_binary_ready)
        print(f"  [OK] getBinaryPathIfReady(): {count1} match(es)")
    else:
        print(f"  [FAIL] getBinaryPathIfReady(): 0 matches, expected >= 1")
        failed = True

    # Patch 2: getStatus() - Return Ready if system binary exists on Linux
    old_status = b'async getStatus(){if(await this.binaryExists(this.requiredVersion))'
    new_status = b'async getStatus(){console.log("[ClaudeCode] getStatus called, platform:",process.platform);if(process.platform==="linux"){try{const fs=require("fs");const exists=fs.existsSync("/usr/bin/claude");console.log("[ClaudeCode] /usr/bin/claude exists:",exists);if(exists){console.log("[ClaudeCode] returning Ready");return Rv.Ready}}catch(e){console.log("[ClaudeCode] error:",e)}}if(await this.binaryExists(this.requiredVersion))'

    count2 = content.count(old_status)
    if count2 >= 1:
        content = content.replace(old_status, new_status)
        print(f"  [OK] getStatus(): {count2} match(es)")
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
