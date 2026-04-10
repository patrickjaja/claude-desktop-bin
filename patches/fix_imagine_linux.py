#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Enable Imagine/Visualize MCP server on Linux.

The Imagine server (internal name "visualize") provides show_widget and read_me
tools that render inline SVG graphics, HTML diagrams, charts, mockups, data
visualizations, and elicitation forms directly in the chat UI. It uses the
ui://imagine/show-widget.html MCP resource with a sandboxed iframe renderer.

Gating: GrowthBook flag 3444158716 + session type "cowork". No platform gate
exists — the server loads unconditionally on all platforms. The only blocker on
Linux is the server-side GrowthBook flag not being enabled.

What we patch:
  A) isEnabled callback: (rn("3444158716")||!1) → (true)
  B) hasImagine variable: rn("3444158716")||!1 → true

The imagineSystemPrompt (extra model guidance) comes from the claude.ai backend
during session creation. Without it, the tools still appear and work — the model
just doesn't get the specialized rendering instructions. When the backend sends
the prompt, it's injected into the system prompt automatically.

Tools provided by the server:
  - show_widget: Render SVG or HTML content inline (charts, diagrams, mockups)
  - read_me: CSS variables, colors, typography, and module-specific guidance

Usage: python3 fix_imagine_linux.py <path_to_index.js>
"""

import sys
import os
import re


EXPECTED_PATCHES = 2


def patch_imagine(filepath):
    """Enable Imagine/Visualize on Linux by forcing GrowthBook flag."""

    print("=== Patch: fix_imagine_linux ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, "rb") as f:
        content = f.read()

    original_content = content
    patches_applied = 0

    # ── Patch A: Force isEnabled in visualize server definition ──────
    #
    # Upstream:  isEnabled:t=>(rn("3444158716")||!1)&&t.sessionType==="cowork"
    # Patched:   isEnabled:t=>(true)&&t.sessionType==="cowork"
    #
    # This enables the server for cowork sessions regardless of GrowthBook.

    already_a = b'isEnabled:t=>(true)&&t.sessionType==="cowork"' in content
    if already_a:
        print("  [OK] isEnabled: already patched (skipped)")
        patches_applied += 1
    else:
        pattern_a = rb'isEnabled:[\w$]+=>\([\w$]+\("3444158716"\)\|\|!1\)&&[\w$]+\.sessionType==="cowork"'
        replacement_a = b'isEnabled:t=>(true)&&t.sessionType==="cowork"'

        content, count = re.subn(pattern_a, replacement_a, content, count=1)
        if count >= 1:
            print(f"  [OK] isEnabled: forced ON for cowork sessions ({count} match)")
            patches_applied += 1
        else:
            print("  [FAIL] isEnabled pattern not found")

    # ── Patch B: Force hasImagine variable for system prompt injection ─
    #
    # Upstream:  ve=rn("3444158716")||!1
    # Patched:   ve=true
    #
    # When true AND the backend sends imagineSystemPrompt, the prompt is
    # injected into the cowork session system prompt. If the backend doesn't
    # send the prompt, this is harmless (the && check prevents injection).

    # Already patched if the flag ID no longer appears in this specific pattern
    already_b = re.search(rb'[\w$]+=[\w$]+\("3444158716"\)\|\|!1', content) is None and b'"3444158716"' not in content
    if already_b:
        print("  [OK] hasImagine: already patched (skipped)")
        patches_applied += 1
    else:
        # Match: <var>=rn("3444158716")||!1
        # The variable name changes per release, so use [\w$]+
        # Replace with <var>=!0 (true) — safe in strict mode, no global leak
        pattern_b = rb'([\w$]+)=[\w$]+\("3444158716"\)\|\|!1'

        def replacement_b(m):
            var = m.group(1)
            return var + b"=!0"

        content, count = re.subn(pattern_b, replacement_b, content, count=1)
        if count >= 1:
            print(f"  [OK] hasImagine: forced true ({count} match)")
            patches_applied += 1
        else:
            print("  [FAIL] hasImagine pattern not found")

    if patches_applied < EXPECTED_PATCHES:
        print(f"  [FAIL] Only {patches_applied}/{EXPECTED_PATCHES} patches applied")
        return False

    if content != original_content:
        with open(filepath, "wb") as f:
            f.write(content)
        print("  [PASS] Imagine/Visualize enabled for cowork sessions")
        return True
    else:
        print("  [OK] Already patched, no changes needed")
        return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_imagine(sys.argv[1])
    sys.exit(0 if success else 1)
