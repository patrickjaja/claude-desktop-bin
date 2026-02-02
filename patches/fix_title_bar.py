#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Fix title bar visibility on Linux by offsetting the child WebContentsView.

On Linux, the child WebContentsView (claude.ai content) is positioned at y=0,
completely covering the parent BrowserWindow's webContents which renders the
React title bar component. This patch changes the offset from 0 to 36px,
leaving a gap at the top where the React title bar shows through.

The companion patch fix_title_bar_renderer.py modifies the React title bar
component to render a functional hamburger menu button on Linux.

Usage: python3 fix_title_bar.py <path_to_index.js>
"""

import sys
import os
import re


def patch_title_bar(filepath):
    """Offset child WebContentsView to expose React title bar on Linux."""

    print(f"=== Patch: fix_title_bar ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content
    failed = False

    # Match the resize callback that positions the child WebContentsView:
    #   const i=()=>{const o=e.getContentBounds(),c=0;
    #   r.setBounds({x:0,y:c,width:o.width,height:o.height-c})
    #
    # We change c=0 to c=36 on Linux, pushing the claude.ai view down
    # to expose the React title bar rendered by the parent BrowserWindow.
    #
    # Pattern uses \w+ for minified variable names.
    pattern = (
        rb'(const \w+=\(\)=>\{const (\w+)=e\.getContentBounds\(\)),(\w+)=0;'
        rb'(\w+)\.setBounds\(\{x:0,y:\3,width:\2\.width,height:\2\.height-\3\}\)'
    )

    def replacement(m):
        resize_start = m.group(1).decode('utf-8')
        o_var = m.group(2).decode('utf-8')
        c_var = m.group(3).decode('utf-8')
        r_var = m.group(4).decode('utf-8')

        # On Linux, offset by 36px for title bar; on other platforms keep 0
        result = (
            f'{resize_start},{c_var}=process.platform==="linux"?36:0;'
            f'{r_var}.setBounds({{x:0,y:{c_var},width:{o_var}.width,height:{o_var}.height-{c_var}}})'
        )
        return result.encode('utf-8')

    content, count = re.subn(pattern, replacement, content, count=1)
    if count == 1:
        print(f"  [OK] Child view offset: c=0 → c=36 on Linux (1 match)")
    else:
        print(f"  [FAIL] setBounds offset pattern: {count} matches, expected 1")
        failed = True

    if failed:
        print("  [FAIL] Required patterns did not match")
        return False

    if content != original_content:
        with open(filepath, 'wb') as f:
            f.write(content)
        print("  [PASS] Title bar offset enabled for Linux")
        return True
    else:
        print("  [WARN] No changes made")
        return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_title_bar(sys.argv[1])
    sys.exit(0 if success else 1)
