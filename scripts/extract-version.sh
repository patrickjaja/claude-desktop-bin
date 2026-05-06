#!/bin/bash
set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <path-to-Claude.msix>"
    exit 1
fi

MSIX_PATH="$1"

if [ ! -f "$MSIX_PATH" ]; then
    echo "Error: File not found: $MSIX_PATH"
    exit 1
fi

REAL_PATH=$(realpath "$MSIX_PATH")
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

7z e -y "$REAL_PATH" -o"$TEMP_DIR" AppxManifest.xml >/dev/null 2>&1 || true

if [ ! -f "$TEMP_DIR/AppxManifest.xml" ]; then
    echo "Error: AppxManifest.xml not found in $MSIX_PATH (is this a valid msix?)" >&2
    exit 1
fi

# msix Identity Version is X.Y.Z.0; strip trailing build component to match upstream X.Y.Z
VERSION=$(python3 -c "
import sys, re, xml.etree.ElementTree as ET
root = ET.parse('$TEMP_DIR/AppxManifest.xml').getroot()
ns = {'m': 'http://schemas.microsoft.com/appx/manifest/foundation/windows10'}
ident = root.find('m:Identity', ns)
v = ident.attrib['Version']
print(re.sub(r'\.0$', '', v))
")

echo "$VERSION"
