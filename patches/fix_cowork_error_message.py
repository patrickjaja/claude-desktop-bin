#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Replace Windows-centric "VM service not running" errors with helpful
Linux messages that guide users to install claude-cowork-service.

Usage: python3 fix_cowork_error_message.py <path_to_index.js>
"""

import sys
import os


def patch_cowork_error_message(filepath):
    """Replace VM service error messages with Linux-friendly guidance."""

    print(f"=== Patch: fix_cowork_error_message ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content
    patches_applied = 0

    # Patch A: ENOENT / retry-exhausted error
    old_a = b'"VM service not running. The service failed to start."'
    new_a = (b'(process.platform==="linux"'
             b'?"Cowork requires claude-cowork-service. '
             b'Install it from github.com/patrickjaja/claude-cowork-service, '
             b'then restart Claude Desktop."'
             b':"VM service not running. The service failed to start.")')

    if old_a in content:
        content = content.replace(old_a, new_a, 1)
        print(f"  [OK] Startup error message: replaced")
        patches_applied += 1
    else:
        print(f"  [WARN] Startup error message not found")

    # Patch B: Timeout fallback error
    old_b = b'throw new Error("VM service not running.")'
    new_b = (b'throw new Error(process.platform==="linux"'
             b'?"Cowork service not responding. '
             b'Make sure claude-cowork-service is running '
             b'(github.com/patrickjaja/claude-cowork-service), '
             b'then restart Claude Desktop."'
             b':"VM service not running.")')

    if old_b in content:
        content = content.replace(old_b, new_b, 1)
        print(f"  [OK] Timeout error message: replaced")
        patches_applied += 1
    else:
        print(f"  [WARN] Timeout error message not found")

    # Check results
    if patches_applied == 0:
        print("  [FAIL] No patches could be applied")
        return False

    if content == original_content:
        print("  [WARN] No changes made (patterns may have already been applied)")
        return True

    # Verify brace balance
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

    success = patch_cowork_error_message(sys.argv[1])
    sys.exit(0 if success else 1)
