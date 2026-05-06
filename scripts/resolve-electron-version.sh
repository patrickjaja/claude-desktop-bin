#!/bin/bash
# resolve-electron-version.sh — Shared helper to resolve the Electron version.
#
# This file is meant to be SOURCED, not executed directly.
# It sets ELECTRON_VERSION in the caller's environment.
#
# Resolution chain:
#   1. If ELECTRON_VERSION is already set in env, keep it (override)
#   2. Read from .electron-version file (searching upward from SCRIPT_DIR)
#   3. Fall back to GitHub API (last resort)
#
# Prerequisites: the caller should have SCRIPT_DIR set to its own directory.
# If not set, we try to derive a sensible default.

# Guard: if ELECTRON_VERSION is already set, respect it
if [ -n "$ELECTRON_VERSION" ]; then
    echo "Using Electron version: $ELECTRON_VERSION (from environment override)" >&2
    return 0 2>/dev/null || exit 0
fi

# Determine where to start looking for .electron-version
_resolve_start="${SCRIPT_DIR:-.}"

# Search common relative paths from SCRIPT_DIR, plus PROJECT_ROOT if set
_found_version_file=""
for _candidate in \
    "$_resolve_start/.electron-version" \
    "$_resolve_start/../.electron-version" \
    "$_resolve_start/../../.electron-version" \
    "${PROJECT_ROOT:+$PROJECT_ROOT/.electron-version}"; do

    # Skip empty candidates (when PROJECT_ROOT is unset)
    [ -z "$_candidate" ] && continue

    if [ -f "$_candidate" ]; then
        _found_version_file="$_candidate"
        break
    fi
done

if [ -n "$_found_version_file" ]; then
    ELECTRON_VERSION="$(tr -d '[:space:]' < "$_found_version_file")"
    export ELECTRON_VERSION
    echo "Using Electron version: $ELECTRON_VERSION (from $_found_version_file)" >&2
    return 0 2>/dev/null || exit 0
fi

# Last resort: GitHub API
echo "Warning: .electron-version not found. Falling back to GitHub API." >&2
echo "  Consider creating .electron-version in the project root." >&2

ELECTRON_VERSION="$(curl -sf https://api.github.com/repos/electron/electron/releases/latest \
    | grep '"tag_name":' \
    | sed -E 's/.*"v([^"]+)".*/\1/' || true)"

if [ -z "$ELECTRON_VERSION" ]; then
    echo "Error: Could not resolve Electron version from any source." >&2
    echo "  Create .electron-version in the project root with the desired version." >&2
    return 1 2>/dev/null || exit 1
fi

export ELECTRON_VERSION
echo "Using Electron version: $ELECTRON_VERSION (from GitHub API)" >&2
