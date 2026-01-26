#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/renderer/main_window/assets/MainWindowPage-*.js
# @patch-type: python
"""
Patch Claude Desktop to show internal title bar on Linux.

v1.1.886+ code structure (comma operator in if condition):
  if(c.useEffect(()=>{...},[]),!W&&e)return ...
  Where W = platform check (imported from main-*.js)

Pre-v1.1.886 code structure:
  if(!B&&e)return null
  Where B = process.platform==="win32" (true on Windows)

Original behavior:
- Windows: negation makes condition false → title bar SHOWS
- Linux: negation makes condition true → returns null → title bar HIDDEN

This patch removes the negation: !VAR&&VAR -> VAR&&VAR
New behavior:
- Windows: condition true → returns null → title bar hidden (uses native)
- Linux: condition false → title bar SHOWS

Usage: python3 fix_title_bar.py <path_to_MainWindowPage-*.js>
"""

import sys
import os
import re


def patch_title_bar(filepath):
    """Patch the title bar detection to show on Linux."""

    print(f"=== Patch: fix_title_bar ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content
    patches_applied = 0

    # Pattern 1: New structure (v1.1.886+) - useEffect with comma operator
    # Matches: []),!W&&e)return
    # Changes: []),!W&&e)return -> []),W&&e)return (removes negation)
    pattern1 = rb'\[\]\),!(\w+)&&(\w+)\)return'
    replacement1 = rb'[]),\1&&\2)return'

    content, count1 = re.subn(pattern1, replacement1, content)
    if count1 > 0:
        patches_applied += count1
        print(f"  [OK] title bar condition (new pattern): {count1} match(es)")

    # Pattern 2: Old structure (pre-v1.1.886) - direct if condition
    # Matches: if(!B&&e)
    # Changes: if(!B&&e) -> if(B&&e) (removes negation)
    if patches_applied == 0:
        pattern2 = rb'if\(!([a-zA-Z_][a-zA-Z0-9_]*)\s*&&\s*([a-zA-Z_][a-zA-Z0-9_]*)\)'
        replacement2 = rb'if(\1&&\2)'

        content, count2 = re.subn(pattern2, replacement2, content)
        if count2 > 0:
            patches_applied += count2
            print(f"  [OK] title bar condition (old pattern): {count2} match(es)")

    # Validation
    if patches_applied == 0:
        print(f"  [FAIL] title bar condition: 0 matches (tried 2 patterns)")
        return False

    # Write back if changed
    if content != original_content:
        with open(filepath, 'wb') as f:
            f.write(content)
        print("  [PASS] Title bar patched successfully")
        return True
    else:
        print("  [WARN] No changes made (patterns may have already been applied)")
        return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_MainWindowPage-*.js>")
        sys.exit(1)

    success = patch_title_bar(sys.argv[1])
    sys.exit(0 if success else 1)
