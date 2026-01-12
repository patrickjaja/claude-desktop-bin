#!/usr/bin/env python3
"""
@patch-target: app.asar.contents/.vite/build/index.js
@patch-type: python

Fix app not quitting after cleanup completes.

After the will-quit handler calls preventDefault() and runs cleanup,
calling app.quit() again becomes a no-op on Linux. The will-quit event
never fires again, leaving the app stuck.

Solution: Use app.exit(0) instead of app.quit() after cleanup is complete.
Since all cleanup handlers have already run (mcp-shutdown, quick-entry-cleanup,
prototype-cleanup), we can safely force exit. Using setImmediate ensures
the exit happens in the next event loop tick.
"""

import sys
import re

def main():
    if len(sys.argv) != 2:
        print("Usage: fix_app_quit.py <file>")
        sys.exit(1)

    file_path = sys.argv[1]

    with open(file_path, 'rb') as f:
        content = f.read()

    print("=== Patch: fix_app_quit ===")
    print(f"  Target: {file_path}")

    # Original pattern: clearTimeout(n)}XX&&YY.app.quit()}
    # Variables change between versions (e.g., S_&&he → TS&&ce)
    # The XX&&YY.app.quit() doesn't work after preventDefault() on Linux
    # Replace with setImmediate + app.exit(0) for reliable exit
    pattern = rb'(clearTimeout\(\w+\)\})(\w+)&&(\w+)(\.app\.quit\(\))'

    def replacement(m):
        flag_var = m.group(2).decode('utf-8')
        electron_var = m.group(3).decode('utf-8')
        return f'{m.group(1).decode("utf-8")}if({flag_var}){{setImmediate(()=>{electron_var}.app.exit(0))}}'.encode('utf-8')

    new_content, count = re.subn(pattern, replacement, content)

    if count == 0:
        print("  [WARN] app.quit pattern: 0 matches (may need pattern update)")
        # Debug: check for any app.quit patterns
        if b'.app.quit()' in content:
            print("  [INFO] Found '.app.quit()' in file but pattern didn't match")
        sys.exit(0)

    print(f"  [OK] app.quit -> app.exit: {count} match(es)")

    with open(file_path, 'wb') as f:
        f.write(new_content)

    print("  [PASS] App quit patched successfully")
    sys.exit(0)

if __name__ == "__main__":
    main()
