#!/usr/bin/env bash
# Guard: docs/claude-desktop-bin.jsonc must equal the template the
# add_growthbook_overrides patch actually writes on first launch.
#
# WHY: the template is authored in js/growthbook_overrides.js (the runtime
# source of truth - it is what the app auto-creates in userData). We also ship
# it as docs/claude-desktop-bin.jsonc so users can browse the full flag catalog
# on GitHub and the README can link it. Those two must never drift, or the
# documented catalog lies about what the app produces. This regenerates the
# template from the JS helper (via the same electron shim used in tests) and
# diffs it against the committed docs file; any difference fails the build.
#
# Regenerate after editing the TEMPLATE in js/growthbook_overrides.js:
#   node scripts/check-jsonc-template-sync.sh --write
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
JS="$REPO_DIR/js/growthbook_overrides.js"
DOCS="$REPO_DIR/docs/claude-desktop-bin.jsonc"
MODE="${1:-check}"

if ! command -v node >/dev/null 2>&1; then
  echo "[jsonc-sync] node not available - skipping (non-fatal)"
  exit 0
fi

TMPDIR_GEN="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_GEN"' EXIT

# Render the template exactly as the app would, using an electron shim so the
# helper's first-run writeFileSync drops the template into TMPDIR_GEN.
node -e "
const Module=require('module');const orig=Module._load;
Module._load=function(r,...a){if(r==='electron')return{app:{getPath:()=>'$TMPDIR_GEN'}};return orig.apply(this,[r,...a])};
process.versions=process.versions||{};process.versions.electron='0';
globalThis.__cdbDiag=()=>{};
require('$JS');
globalThis.__cdbApplyGbOverrides({});
"
GEN="$TMPDIR_GEN/claude-desktop-bin.jsonc"
if [ ! -f "$GEN" ]; then
  echo "[jsonc-sync] ERROR: helper did not write a template - check js/growthbook_overrides.js"
  exit 1
fi

if [ "$MODE" = "--write" ]; then
  cp "$GEN" "$DOCS"
  echo "[jsonc-sync] wrote $DOCS from js/growthbook_overrides.js"
  exit 0
fi

if ! diff -u "$DOCS" "$GEN" > /dev/null 2>&1; then
  echo "::error::docs/claude-desktop-bin.jsonc is out of sync with the template in js/growthbook_overrides.js"
  echo "Regenerate it:  node scripts/check-jsonc-template-sync.sh --write   (then commit)"
  echo "--- diff (docs vs generated) ---"
  diff -u "$DOCS" "$GEN" || true
  exit 1
fi
echo "[jsonc-sync] docs/claude-desktop-bin.jsonc matches the shipped template"
