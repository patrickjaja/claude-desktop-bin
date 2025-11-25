#!/bin/bash
#
# Validate all patches against an extracted app.asar.contents directory
#
# This script tests each patch against target files WITHOUT modifying them,
# allowing you to verify patches will work before running a full build.
#
# Usage:
#   ./scripts/validate-patches.sh <app.asar.contents_path>
#   ./scripts/validate-patches.sh                         # Uses current dir
#
# Example workflow:
#   1. Download and extract Claude Desktop
#   2. Extract app.asar: asar extract app.asar app.asar.contents
#   3. Run: ./scripts/validate-patches.sh ./app.asar.contents
#
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PATCHES_DIR="$PROJECT_DIR/patches"

APP_CONTENTS="${1:-.}"

# Check if the directory looks like an app.asar.contents
if [ ! -d "$APP_CONTENTS/.vite" ]; then
    echo "Error: Invalid app.asar.contents directory"
    echo "Expected to find .vite/ directory in: $APP_CONTENTS"
    echo ""
    echo "Usage: $0 <path_to_app.asar.contents>"
    echo ""
    echo "Example:"
    echo "  asar extract app.asar app.asar.contents"
    echo "  $0 ./app.asar.contents"
    exit 1
fi

echo "==================================="
echo "  Patch Validation Report"
echo "==================================="
echo "App contents: $APP_CONTENTS"
echo ""

TOTAL=0
PASSED=0
FAILED=0
SKIPPED=0

for patch_file in "$PATCHES_DIR"/*.py "$PATCHES_DIR"/*.js; do
    [ -f "$patch_file" ] || continue

    TOTAL=$((TOTAL + 1))
    filename=$(basename "$patch_file")

    # Extract metadata
    target=$(grep -m1 '@patch-target:' "$patch_file" 2>/dev/null | sed 's/.*@patch-target:[[:space:]]*//' | tr -d '\r' || echo "")
    patch_type=$(grep -m1 '@patch-type:' "$patch_file" 2>/dev/null | sed 's/.*@patch-type:[[:space:]]*//' | tr -d '\r' || echo "")

    if [ -z "$target" ]; then
        echo "[$filename]"
        echo "  Status: SKIP (no @patch-target metadata)"
        SKIPPED=$((SKIPPED + 1))
        echo ""
        continue
    fi

    echo "[$filename]"
    echo "  Target: $target"
    echo "  Type: $patch_type"

    # Resolve the target path (handle glob patterns)
    if [[ "$target" == *"*"* ]]; then
        # Has glob pattern - use find
        dir_part=$(dirname "$target")
        file_pattern=$(basename "$target")
        # Strip app.asar.contents/ prefix if present
        search_dir="$APP_CONTENTS/${dir_part#app.asar.contents/}"
        actual_target=$(find "$search_dir" -name "$file_pattern" 2>/dev/null | head -1)
    else
        # Direct path - strip app.asar.contents/ prefix if present
        actual_target="$APP_CONTENTS/${target#app.asar.contents/}"
    fi

    if [ -z "$actual_target" ] || [ ! -f "$actual_target" ]; then
        echo "  Status: FAIL (target file not found)"
        echo "  Searched: $search_dir/$file_pattern"
        FAILED=$((FAILED + 1))
        echo ""
        continue
    fi

    echo "  Resolved: $actual_target"

    # For Python patches, run them on a copy of the file
    if [ "$patch_type" = "python" ]; then
        tmp_file=$(mktemp)
        cp "$actual_target" "$tmp_file"

        if python3 "$patch_file" "$tmp_file" 2>&1 | sed 's/^/  /'; then
            echo "  Status: PASS"
            PASSED=$((PASSED + 1))
        else
            echo "  Status: FAIL"
            FAILED=$((FAILED + 1))
        fi

        rm -f "$tmp_file"
    elif [ "$patch_type" = "replace" ]; then
        # For replace patches, just check target exists
        echo "  Status: PASS (file replacement)"
        PASSED=$((PASSED + 1))
    else
        echo "  Status: SKIP (unknown type: $patch_type)"
        SKIPPED=$((SKIPPED + 1))
    fi

    echo ""
done

echo "==================================="
echo "  Summary"
echo "==================================="
echo "  Total:   $TOTAL"
echo "  Passed:  $PASSED"
echo "  Failed:  $FAILED"
echo "  Skipped: $SKIPPED"
echo "==================================="

if [ $FAILED -gt 0 ]; then
    echo ""
    echo "VALIDATION FAILED - $FAILED patch(es) did not match"
    echo "Please update the patches to match the new file structure."
    exit 1
fi

echo ""
echo "All patches validated successfully!"
exit 0
