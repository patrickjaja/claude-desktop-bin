#!/bin/bash
# verify-electron.sh — Shared helper to verify a downloaded Electron zip.
#
# This file is meant to be SOURCED, not executed directly. It defines:
#
#   verify_electron_zip <zip_path> <arch>
#       <arch> is "x64" or "arm64" (the Electron release naming).
#       Verifies <zip_path> against the pinned digest in .electron-shasums
#       for the resolved ELECTRON_VERSION. Returns non-zero (and the caller's
#       `set -e` aborts the build) on mismatch or missing digest.
#
# Prerequisites: ELECTRON_VERSION must already be set (callers source
# resolve-electron-version.sh first). SCRIPT_DIR should point at scripts/'s
# location; if unset we derive it from this file.

# Locate .electron-shasums relative to this helper (scripts/ lives in project root).
_VERIFY_ELECTRON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_ELECTRON_SHASUMS="${ELECTRON_SHASUMS_FILE:-$(dirname "$_VERIFY_ELECTRON_DIR")/.electron-shasums}"

verify_electron_zip() {
    local zip_path="$1"
    local arch="$2"

    if [ -z "${ELECTRON_VERSION:-}" ]; then
        echo "verify_electron_zip: ELECTRON_VERSION not set (source resolve-electron-version.sh first)" >&2
        return 1
    fi
    if [ ! -f "$zip_path" ]; then
        echo "verify_electron_zip: file not found: $zip_path" >&2
        return 1
    fi
    if [ ! -f "$_ELECTRON_SHASUMS" ]; then
        echo "verify_electron_zip: $_ELECTRON_SHASUMS missing (run scripts/update-electron-shasums.sh)" >&2
        return 1
    fi

    local zip_name="electron-v${ELECTRON_VERSION}-linux-${arch}.zip"
    local expected
    expected="$(awk -v n="$zip_name" '$2 == n {print $1}' "$_ELECTRON_SHASUMS")"
    if [ -z "$expected" ]; then
        echo "verify_electron_zip: no pinned digest for $zip_name in $_ELECTRON_SHASUMS" >&2
        echo "  (run scripts/update-electron-shasums.sh after bumping .electron-version)" >&2
        return 1
    fi

    local actual
    actual="$(sha256sum "$zip_path" | awk '{print $1}')"
    if [ "$actual" != "$expected" ]; then
        echo "verify_electron_zip: SHA-256 MISMATCH for $zip_name" >&2
        echo "  expected: $expected" >&2
        echo "  actual:   $actual" >&2
        return 1
    fi

    echo "verify_electron_zip: $zip_name SHA-256 OK ($expected)" >&2
    return 0
}
