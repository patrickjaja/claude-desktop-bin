#!/bin/bash
# update-rpm-repo.sh — Build RPM repository metadata from .rpm files
#
# Usage: update-rpm-repo.sh <rpm_file> <repo_dir> <gpg_key_id>
#
# 1. Copies new .rpm into repo_dir/rpm/x86_64/
# 2. Prunes old versions (keeps latest 1)
# 3. Runs createrepo_c to generate repodata/
# 4. GPG-signs repodata/repomd.xml (detached armored signature)

set -euo pipefail

RPM_FILE="$1"
REPO_DIR="$2"
GPG_KEY_ID="$3"

if [ ! -f "$RPM_FILE" ]; then
  echo "ERROR: .rpm file not found: $RPM_FILE"
  exit 1
fi

echo "=== Updating RPM repository ==="
echo "  .rpm file:  $RPM_FILE"
echo "  Repo dir:   $REPO_DIR"
echo "  GPG key:    $GPG_KEY_ID"

# Create directory structure
mkdir -p "$REPO_DIR/rpm/x86_64"

# Copy new .rpm
cp "$RPM_FILE" "$REPO_DIR/rpm/x86_64/"
echo "Copied $(basename "$RPM_FILE") to rpm/x86_64/"

# Prune old versions — keep only the latest 1 to avoid gh-pages repo bloat
cd "$REPO_DIR/rpm/x86_64"
# shellcheck disable=SC2012
ls -t *.rpm 2>/dev/null | tail -n +2 | xargs -r rm -f
KEPT=$(ls -1 *.rpm 2>/dev/null | wc -l)
echo "Kept $KEPT .rpm file(s) after pruning"

# Generate repository metadata
cd "$REPO_DIR/rpm"
createrepo_c --update .
echo "Generated repodata/"

# GPG sign repomd.xml (detached armored signature)
rm -f repodata/repomd.xml.asc
gpg --batch --yes --default-key "$GPG_KEY_ID" --detach-sign --armor \
  -o repodata/repomd.xml.asc repodata/repomd.xml
echo "Signed repodata/repomd.xml"

echo "=== RPM repository updated ==="
