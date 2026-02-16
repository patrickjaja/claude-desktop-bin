#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Fix cross-device rename errors on Linux.

On Linux, /tmp is often a separate tmpfs filesystem. The app downloads VM
bundles to /tmp and then tries fs.rename() to move them to ~/.config/Claude/.
rename() fails with EXDEV when source and destination are on different
filesystems.

This patch replaces unguarded fs/promises rename calls with a cross-device-safe
wrapper that falls back to copyFile+unlink when rename fails with EXDEV.
Uses flexible pattern for the fs module name (changes between versions)
and negative lookbehind to skip calls already inside try blocks.

Error: EXDEV: cross-device link not permitted, rename '/tmp/wvm-xxx/rootfs.vhdx'
       -> '/home/user/.config/Claude/vm_bundles/claudevm.bundle/rootfs.vhdx'

Usage: python3 fix_cross_device_rename.py <path_to_index.js>
"""

import sys
import os
import re


def patch_cross_device_rename(filepath):
    """Replace fs.rename with cross-device-safe wrapper on Linux."""

    print(f"=== Patch: fix_cross_device_rename ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content

    # Replace each await <mod>.rename(x,y) call with an inline EXDEV-safe
    # fallback. This avoids scoping issues — the minified bundle has many
    # closures, and a helper function injected in one scope wouldn't be
    # visible in others. The inline approach is self-contained at each call site.
    #
    # The fs module name changes between versions (zr, ur, Xe, etc.), so we
    # use \w+ to match any name. The (?<!try\{) lookbehind skips rename calls
    # that are already inside a try block with their own EXDEV handler.
    #
    # Before: await ur.rename(x,y)
    # After:  await ur.rename(x,y).catch(async e=>{if(e.code==="EXDEV"){await ur.copyFile(x,y);await ur.unlink(x)}else throw e})
    rename_pattern = rb'(?<!try\{)await (\w+)\.rename\((\w+),(\w+)\)'

    def rename_replacement(m):
        mod = m.group(1)
        src = m.group(2)
        dst = m.group(3)
        return (b'await ' + mod + b'.rename(' + src + b',' + dst + b')'
                b'.catch(async e=>{if(e.code==="EXDEV"){'
                b'await ' + mod + b'.copyFile(' + src + b',' + dst + b');'
                b'await ' + mod + b'.unlink(' + src + b')'
                b'}else throw e})')

    content, count = re.subn(rename_pattern, rename_replacement, content)
    if count >= 1:
        print(f"  [OK] Replaced {count} rename() calls with inline EXDEV fallback")
    else:
        print(f"  [WARN] No unguarded rename() calls found")

    if content == original_content:
        print("  [WARN] No changes made")
        return True

    # Verify brace balance
    original_delta = original_content.count(b'{') - original_content.count(b'}')
    patched_delta = content.count(b'{') - content.count(b'}')
    if original_delta != patched_delta:
        diff = patched_delta - original_delta
        print(f"  [FAIL] Patch introduced brace imbalance: {diff:+d}")
        return False

    with open(filepath, 'wb') as f:
        f.write(content)
    print(f"  [PASS] Cross-device rename fix applied")
    return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_cross_device_rename(sys.argv[1])
    sys.exit(0 if success else 1)
