#!/bin/bash
# update-electron-shasums.sh — Pin the official Electron zip SHA-256 digests.
#
# Fetches the official SHASUMS256.txt published by the Electron project for the
# pinned version (.electron-version) and (re)writes .electron-shasums with the
# linux-x64 and linux-arm64 digests in `sha256sum -c` compatible format.
#
# Run this whenever .electron-version is bumped. It is also used in --check mode
# by CI to verify the committed .electron-shasums matches the pinned version.
#
# Usage:
#   ./scripts/update-electron-shasums.sh           # write/update .electron-shasums
#   ./scripts/update-electron-shasums.sh --check    # verify only, non-zero on drift
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SHASUMS_FILE="$PROJECT_DIR/.electron-shasums"

CHECK_ONLY=0
if [ "${1:-}" = "--check" ]; then
    CHECK_ONLY=1
fi

# Resolve the pinned Electron version (.electron-version, overridable via env).
source "$SCRIPT_DIR/resolve-electron-version.sh"

UPSTREAM_URL="https://github.com/electron/electron/releases/download/v${ELECTRON_VERSION}/SHASUMS256.txt"
echo "Fetching official Electron digests: $UPSTREAM_URL" >&2

SHASUMS_RAW="$(curl -fsSL "$UPSTREAM_URL")"
if [ -z "$SHASUMS_RAW" ]; then
    echo "Error: failed to fetch SHASUMS256.txt for Electron v${ELECTRON_VERSION}" >&2
    exit 1
fi

# Extract the two linux archives we ship. Upstream lines look like:
#   83c7178...b4  *electron-v42.0.0-linux-x64.zip
# Normalize the leading "*" (binary marker) to the standard two-space form so
# `sha256sum -c` accepts it.
GENERATED=""
for arch in x64 arm64; do
    zip="electron-v${ELECTRON_VERSION}-linux-${arch}.zip"
    line="$(printf '%s\n' "$SHASUMS_RAW" | grep -E "[[:space:]]\*?${zip}\$" || true)"
    if [ -z "$line" ]; then
        echo "Error: digest for $zip not found in upstream SHASUMS256.txt" >&2
        exit 1
    fi
    digest="$(printf '%s\n' "$line" | awk '{print $1}')"
    GENERATED="${GENERATED}${digest}  ${zip}"$'\n'
done

if [ "$CHECK_ONLY" -eq 1 ]; then
    if [ ! -f "$SHASUMS_FILE" ]; then
        echo "Error: $SHASUMS_FILE missing. Run: ./scripts/update-electron-shasums.sh" >&2
        exit 1
    fi
    if ! diff <(printf '%s' "$GENERATED") "$SHASUMS_FILE" >/dev/null 2>&1; then
        echo "Error: .electron-shasums is out of sync with Electron v${ELECTRON_VERSION}." >&2
        echo "Run: ./scripts/update-electron-shasums.sh" >&2
        echo "--- expected ---" >&2
        printf '%s' "$GENERATED" >&2
        echo "--- committed ---" >&2
        cat "$SHASUMS_FILE" >&2
        exit 1
    fi
    echo ".electron-shasums matches Electron v${ELECTRON_VERSION} (OK)" >&2
    exit 0
fi

printf '%s' "$GENERATED" > "$SHASUMS_FILE"
echo "Wrote $SHASUMS_FILE for Electron v${ELECTRON_VERSION}:" >&2
cat "$SHASUMS_FILE" >&2
