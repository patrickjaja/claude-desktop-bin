#!/bin/bash
# update-apt-repo.sh — Build APT repository metadata from .deb files
#
# Usage: update-apt-repo.sh <deb_file> <repo_dir> <gpg_key_id>
#
# Multi-arch support: the architecture is auto-detected from the .deb filename.
# The script places packages in deb/<arch>/ subdirectories and generates
# a combined Packages index covering all architectures.
#
# 1. Auto-detects arch from .deb filename (amd64 or arm64)
# 2. Copies new .deb into repo_dir/deb/<arch>/
# 3. Prunes old versions per arch (keeps latest 1)
# 4. Generates Packages, Packages.gz, Release (covering all arches)
# 5. GPG-signs Release (Release.gpg + InRelease)

set -euo pipefail

DEB_FILE="$1"
REPO_DIR="$2"
GPG_KEY_ID="$3"

if [ ! -f "$DEB_FILE" ]; then
  echo "ERROR: .deb file not found: $DEB_FILE"
  exit 1
fi

# Auto-detect architecture from .deb filename (e.g., _amd64.deb or _arm64.deb)
DEB_BASENAME=$(basename "$DEB_FILE")
if [[ "$DEB_BASENAME" =~ _([a-z0-9]+)\.deb$ ]]; then
    DEB_ARCH="${BASH_REMATCH[1]}"
else
    echo "WARNING: Could not detect arch from filename, defaulting to amd64"
    DEB_ARCH="amd64"
fi

echo "=== Updating APT repository ==="
echo "  .deb file:  $DEB_FILE"
echo "  Arch:       $DEB_ARCH"
echo "  Repo dir:   $REPO_DIR"
echo "  GPG key:    $GPG_KEY_ID"

# Create directory structure for this architecture
mkdir -p "$REPO_DIR/deb/$DEB_ARCH"

# Copy new .deb
cp "$DEB_FILE" "$REPO_DIR/deb/$DEB_ARCH/"
echo "Copied $DEB_BASENAME to deb/$DEB_ARCH/"

# Prune old versions within this arch — keep only the latest 1
cd "$REPO_DIR/deb/$DEB_ARCH"
# shellcheck disable=SC2012
ls -t *.deb 2>/dev/null | tail -n +2 | xargs -r rm -f
KEPT=$(ls -1 *.deb 2>/dev/null | wc -l)
echo "Kept $KEPT .deb file(s) in $DEB_ARCH after pruning"

# Generate combined Packages index covering all architectures
cd "$REPO_DIR/deb"

# Build Packages from all arch subdirectories
> Packages
for arch_dir in */; do
    arch_dir="${arch_dir%/}"
    [ -d "$arch_dir" ] || continue
    # Only process directories that contain .deb files
    if ls "$arch_dir"/*.deb &>/dev/null; then
        dpkg-scanpackages --multiversion --arch "$arch_dir" "$arch_dir/" >> Packages
    fi
done

gzip -9c Packages > Packages.gz
echo "Generated Packages index ($(wc -l < Packages) lines, arches: $(ls -d */ 2>/dev/null | tr -d '/' | tr '\n' ' '))"

# Generate Release file
apt-ftparchive release . > Release
echo "Generated Release file"

# GPG sign
rm -f Release.gpg InRelease
gpg --batch --yes --default-key "$GPG_KEY_ID" --detach-sign --armor -o Release.gpg Release
gpg --batch --yes --default-key "$GPG_KEY_ID" --clearsign -o InRelease Release
echo "Signed Release (Release.gpg + InRelease)"

echo "=== APT repository updated ==="
