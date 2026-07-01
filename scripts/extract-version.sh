#!/bin/bash
#
# extract-version.sh — print the Claude Desktop version from an official Linux .deb
# (or from an apt Packages index URL: the highest claude-desktop version it lists).
#
# Usage:
#   ./scripts/extract-version.sh <path-to-claude-desktop_*.deb>
#   ./scripts/extract-version.sh <apt-Packages-index-URL> [arch]   # arch default: amd64
#
set -euo pipefail

SRC="${1:-}"
ARCH="${2:-amd64}"

if [ -z "$SRC" ]; then
    echo "Usage: $0 <deb-path-or-apt-Packages-URL> [arch]" >&2
    exit 1
fi

if [ -f "$SRC" ]; then
    # Local .deb: crack control.tar.* with ar+tar (no dpkg-deb dependency) and
    # read the Version field from DEBIAN/control.
    command -v ar >/dev/null 2>&1 || { echo "Error: 'ar' (binutils) not found" >&2; exit 1; }
    TMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TMP_DIR"' EXIT
    # `ar x` doesn't glob member names, so extract the whole archive then pick the
    # control tarball (.deb members: debian-binary, control.tar.*, data.tar.*).
    REAL_DEB="$(realpath "$SRC")"
    ( cd "$TMP_DIR" && ar x "$REAL_DEB" )
    CONTROL_TAR=$(ls "$TMP_DIR"/control.tar.* 2>/dev/null | head -1)
    if [ -z "$CONTROL_TAR" ]; then
        echo "Error: control.tar.* not found in $SRC (is this a valid .deb?)" >&2
        exit 1
    fi
    tar -xf "$CONTROL_TAR" -C "$TMP_DIR"
    VERSION=$(awk -F': ' '/^Version:/{print $2; exit}' "$TMP_DIR/control" | tr -d '[:space:]')
    if [ -z "$VERSION" ]; then
        echo "Error: no Version field in .deb control" >&2
        exit 1
    fi
    echo "$VERSION"
elif [[ "$SRC" =~ ^https?:// ]]; then
    command -v curl >/dev/null 2>&1 || { echo "Error: 'curl' not found" >&2; exit 1; }
    curl -fsSL "$SRC" | python3 - "$ARCH" <<'PY'
import sys
from functools import cmp_to_key
want_arch = sys.argv[1]
blob = sys.stdin.read()
def parse(stanza):
    d = {}
    for line in stanza.splitlines():
        if line[:1].isspace() or ":" not in line:
            continue
        k, _, v = line.partition(":")
        d[k.strip()] = v.strip()
    return d
def vercmp(a, b):
    pa = [int(x) for x in a.replace("-", ".").split(".") if x.isdigit()]
    pb = [int(x) for x in b.replace("-", ".").split(".") if x.isdigit()]
    return (pa > pb) - (pa < pb)
vers = [d["Version"] for d in map(parse, blob.split("\n\n"))
        if d.get("Package") == "claude-desktop" and d.get("Architecture") == want_arch and "Version" in d]
if not vers:
    sys.stderr.write(f"No claude-desktop {want_arch} version in index\n"); sys.exit(1)
print(sorted(vers, key=cmp_to_key(vercmp))[-1])
PY
else
    echo "Error: argument is neither a local file nor an http(s) URL: $SRC" >&2
    exit 1
fi
