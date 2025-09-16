#!/bin/bash
set -e

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

if [ -z "$1" ]; then
    echo "Usage: $0 <path-to-Claude-Setup-x64.exe>"
    exit 1
fi

EXE_PATH="$1"

if [ ! -f "$EXE_PATH" ]; then
    echo "Error: File not found: $EXE_PATH"
    exit 1
fi

REAL_PATH=$(realpath "$EXE_PATH")
7z x -y "$REAL_PATH" -o"$TEMP_DIR" >/dev/null 2>&1 || true

cd "$TEMP_DIR"
NUPKG_FILE=$(ls AnthropicClaude-*.nupkg 2>/dev/null | head -1)

if [ -z "$NUPKG_FILE" ]; then
    echo "Error: Could not find AnthropicClaude nupkg file"
    exit 1
fi

VERSION=$(echo "$NUPKG_FILE" | sed 's/AnthropicClaude-\(.*\)-full\.nupkg/\1/')

echo "$VERSION"