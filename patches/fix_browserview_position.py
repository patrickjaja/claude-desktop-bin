#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Patch Claude Desktop to fix BrowserView positioning on Linux.

The BrowserView needs to be positioned below the internal title bar.
Original code only offsets on Windows, but Linux also needs the offset.

Original: c=Ds?eS+1:0  (only Windows gets offset)
Fixed:    c=Pn?0:eS+1  (macOS gets 0, Windows/Linux get offset)
"""

import sys
import os
import re


def patch_browserview_position(filepath):
    """Patch BrowserView setBounds to include title bar offset on Linux."""

    print(f"=== Patch: fix_browserview_position ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content

    # Step 1: Find darwin platform variable (Pn = process.platform==="darwin")
    darwin_match = re.search(rb'(\w+)=process\.platform==="darwin"', content)
    if not darwin_match:
        print(f"  [FAIL] darwin platform variable: not found")
        return False
    darwin_var = darwin_match.group(1)
    print(f"  [OK] darwin variable: '{darwin_var.decode()}'")

    # Step 2: Find win32 platform variable (Ds = process.platform==="win32")
    win32_match = re.search(rb'(\w+)=process\.platform==="win32"', content)
    if not win32_match:
        print(f"  [FAIL] win32 platform variable: not found")
        return False
    win32_var = win32_match.group(1)
    print(f"  [OK] win32 variable: '{win32_var.decode()}'")

    # Step 3: Replace the BrowserView offset calculation
    # Pattern: ,c=Ds?eS+1:0; -> ,c=Pn?0:eS+1;
    pattern = rb'(,\w+=)' + win32_var + rb'\?(\w+)\+1:0(;)'

    def replacement_func(m):
        prefix = m.group(1)      # ,c=
        height_var = m.group(2)  # eS
        suffix = m.group(3)      # ;
        return prefix + darwin_var + b'?0:' + height_var + b'+1' + suffix

    content, count = re.subn(pattern, replacement_func, content)

    if count > 0:
        print(f"  [OK] setBounds offset: {count} match(es)")
    else:
        print(f"  [FAIL] setBounds offset pattern: no matches")
        return False

    if content != original_content:
        with open(filepath, 'wb') as f:
            f.write(content)
        print("  [PASS] BrowserView position patched successfully")
        return True
    else:
        print("  [WARN] No changes made")
        return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_browserview_position(sys.argv[1])
    sys.exit(0 if success else 1)
