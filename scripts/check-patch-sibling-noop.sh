#!/usr/bin/env bash
# Guard against the "sibling-file no-op" anti-pattern in Nim patches.
#
# WHY THIS EXISTS
# ---------------
# The patch orchestrator (scripts/apply_patches.py) stages each patch's
# @patch-target into an ISOLATED tmpfs copy (tempfile.NamedTemporaryFile) and runs
# the compiled patch binary against THAT copy. So a patch can only reliably touch
# the single file named in its `@patch-target:` header.
#
# Any patch that tries to ALSO patch a *different* file by deriving its path from
# the staged target — e.g. `parentDir(filePath) / "index.pre.js"` or
# `filePath.parentDir / "mainView.js"` — is a GUARANTEED NO-OP through the build:
# the sibling file is never present next to the staged temp copy, so the patch
# silently skips it. This is exactly how v1.15200.0 shipped with the enterprise
# bootstrap (index.pre.js) and the local-agent-mode mainView.js spoof unpatched,
# while still reporting success.
#
# The CORRECT way to patch a second file is to give it its OWN patch file with its
# own `@patch-target:` header (the orchestrator groups by target and stages each
# independently). See fix_enterprise_config_linux_pre.nim / fix_locale_paths_pre.nim.
#
# This guard greps for the dead-code shape and fails the build if it reappears.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
PATCHES_DIR="${1:-$REPO_DIR/patches}"

echo "=== Checking for sibling-file no-op anti-pattern in patches/*.nim ==="

# The smell: deriving a SECOND file path from the patch's own target dir.
# `parentDir(<x>)/ "<file>"` or `<x>.parentDir / "<file>"` where <file> is a
# bundle file the patch then reads/writes. We match the path-derivation forms;
# any hit must be justified (and there should be none, now that second files are
# their own @patch-target).
#
# Patterns (Nim):
#   parentDir(filePath) / "index.pre.js"
#   filePath.parentDir / "mainView.js"
#   <var>.parentDir / "..."
SMELL_RE='(parentDir\([[:alnum:]_]+\)[[:space:]]*/[[:space:]]*"|\.parentDir[[:space:]]*/[[:space:]]*")'

# Scan CODE only — strip Nim comments first so prose that *describes* the
# anti-pattern (e.g. in a header explaining why a sibling patch was removed) does
# not trip the guard. A Nim line comment is `#` that is not inside a string; for a
# path-derivation expression the conservative rule "drop everything from the first
# unindented-or-inline `#`" is sufficient because these expressions never contain
# a literal `#`. We drop any line whose first non-space char is `#`, and for inline
# comments we cut at ` #`.
hits=""
for f in "$PATCHES_DIR"/*.nim; do
  [ -f "$f" ] || continue
  while IFS= read -r line; do
    lineno="${line%%:*}"
    text="${line#*:}"
    # Skip full-line comments (first non-space char is #)
    trimmed="${text#"${text%%[![:space:]]*}"}"
    case "$trimmed" in
      '#'*) continue ;;
    esac
    # Cut inline comments (space-hash) before testing
    code="${text%% #*}"
    if printf '%s' "$code" | grep -qE "$SMELL_RE"; then
      hits="${hits}${f}:${lineno}:${text}"$'\n'
    fi
  done < <(grep -nE "$SMELL_RE" "$f" 2>/dev/null || true)
done
hits="${hits%$'\n'}"

if [ -n "$hits" ]; then
  echo "::error::Found sibling-file no-op anti-pattern (a patch derives a SECOND"
  echo "::error::file path from its staged target — the orchestrator stages each"
  echo "::error::@patch-target in isolation, so this silently patches NOTHING)."
  echo "::error::Give the second file its own @patch-target patch instead."
  echo "::error::See scripts/check-patch-sibling-noop.sh header for the full why."
  echo
  echo "Offending lines:"
  echo "$hits" | sed 's/^/  /'
  exit 1
fi

echo "OK: no patch derives a second file path from its staged target."
echo "    (Second-file patches must use their own @patch-target — e.g."
echo "     fix_enterprise_config_linux_pre.nim targets index.pre.js directly.)"
