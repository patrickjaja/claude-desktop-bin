#!/usr/bin/env python3
"""
@patch-target: app.asar.contents/.vite/build/index.js
@patch-type: python

Fix UtilityProcess not terminating on app exit.

When using the integrated Node.js server for MCP, the fallback kill
after SIGTERM timeout sends another SIGTERM instead of SIGKILL,
causing the process to remain alive and preventing app exit.

Original pattern found in code:
  const a=(s=this.process)==null?void 0:s.kill();te.info(`Killing utiltiy proccess again

Note: "utiltiy" and "proccess" are typos in the original Anthropic code.
"""

import sys
import re

def main():
    if len(sys.argv) != 2:
        print("Usage: fix_utility_process_kill.py <file>")
        sys.exit(1)

    file_path = sys.argv[1]

    with open(file_path, 'rb') as f:
        content = f.read()

    print("=== Patch: fix_utility_process_kill ===")
    print(f"  Target: {file_path}")

    # Pattern: The setTimeout callback that tries to kill the UtilityProcess
    # after 5 seconds. Matches:
    #   const a=(s=this.process)==null?void 0:s.kill();te.info(`Killing utiltiy proccess again
    # Uses \w+ to capture minified variable names (s, a) flexibly
    pattern = rb'(const \w+=\(\w+=this\.process\)==null\?void 0:\w+)(\.kill\(\))(;\w+\.info\(`Killing utiltiy proccess again)'

    def replacement(m):
        # Replace .kill() with .kill("SIGKILL")
        return m.group(1) + b'.kill("SIGKILL")' + m.group(3)

    new_content, count = re.subn(pattern, replacement, content)

    if count == 0:
        print("  [WARN] UtilityProcess kill pattern: 0 matches (may need pattern update)")
        # Debug: show what we're looking for
        if b'Killing utiltiy proccess again' in content:
            print("  [INFO] Found 'Killing utiltiy proccess again' string in file")
            # Try to find nearby context
            ctx = re.search(rb'.{50}Killing utiltiy proccess again.{20}', content)
            if ctx:
                print(f"  [DEBUG] Context: {ctx.group(0)}")
        print("  [PASS] No changes needed (pattern may have changed)")
        sys.exit(0)  # Don't fail build, just warn

    print(f"  [OK] UtilityProcess SIGKILL fix: {count} match(es)")

    with open(file_path, 'wb') as f:
        f.write(new_content)

    print("  [PASS] UtilityProcess kill patched successfully")
    sys.exit(0)

if __name__ == "__main__":
    main()
