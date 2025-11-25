#!/usr/bin/env python3
"""
Patch Claude Desktop title bar detection issue on Linux.

The original code has a negated condition that causes issues on Linux.
This patch fixes: if(!var1 && var2) -> if(var1 && var2)

Usage: python3 fix_title_bar.py <path_to_MainWindowPage-*.js>
"""

import sys
import os
import re


def patch_title_bar(filepath):
    """Patch the title bar detection logic."""

    print(f"Patching title bar in: {filepath}")

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content

    # Fix: if(!var && var2) -> if(var && var2)
    # Pattern: if(!X && Y) where X and Y are variable names
    pattern = rb'if\(!([a-zA-Z_][a-zA-Z0-9_]*)\s*&&\s*([a-zA-Z_][a-zA-Z0-9_]*)\)'
    replacement = rb'if(\1 && \2)'

    content, count = re.subn(pattern, replacement, content)

    if content != original_content:
        with open(filepath, 'wb') as f:
            f.write(content)
        print(f"Title bar patch applied: {count} replacement(s)")
        return True
    else:
        print("Warning: No title bar patterns found to patch")
        return False


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_MainWindowPage-*.js>")
        sys.exit(1)

    filepath = sys.argv[1]
    if not os.path.exists(filepath):
        print(f"Error: File not found: {filepath}")
        sys.exit(1)

    success = patch_title_bar(filepath)
    sys.exit(0 if success else 1)
