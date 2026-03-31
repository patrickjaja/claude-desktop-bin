#!/bin/bash
# update-rpm-repo.sh — Sign RPM and build repository metadata
#
# Usage: update-rpm-repo.sh <rpm_file> <repo_dir> <gpg_key_id>
#
# IMPORTANT: This script must run inside a Fedora/RHEL container (or host)
# where rpm-sign and createrepo_c are native packages. Do NOT run on Ubuntu.
#
# 1. Auto-detects arch from .rpm filename (x86_64 or aarch64)
# 2. Copies new .rpm into repo_dir/rpm/<arch>/
# 3. GPG-signs the RPM package (rpmsign --addsign)
# 4. Verifies the signature (rpm -K)
# 5. Prunes old versions per arch (keeps latest 1)
# 6. Runs createrepo_c to generate repodata/
# 7. GPG-signs repodata/repomd.xml (detached armored signature)

set -euo pipefail

RPM_FILE="$1"
REPO_DIR="$2"
GPG_KEY_ID="$3"

if [ ! -f "$RPM_FILE" ]; then
  echo "ERROR: .rpm file not found: $RPM_FILE"
  exit 1
fi

# Auto-detect architecture from .rpm filename (e.g., .x86_64.rpm or .aarch64.rpm)
RPM_BASENAME=$(basename "$RPM_FILE")
if [[ "$RPM_BASENAME" =~ \.(x86_64|aarch64|noarch)\.rpm$ ]]; then
    RPM_ARCH="${BASH_REMATCH[1]}"
else
    echo "WARNING: Could not detect arch from filename, defaulting to x86_64"
    RPM_ARCH="x86_64"
fi

echo "=== Updating RPM repository ==="
echo "  .rpm file:  $RPM_FILE"
echo "  Arch:       $RPM_ARCH"
echo "  Repo dir:   $REPO_DIR"
echo "  GPG key:    $GPG_KEY_ID"

# Create directory structure for this architecture
mkdir -p "$REPO_DIR/rpm/$RPM_ARCH"

# Copy new .rpm
cp "$RPM_FILE" "$REPO_DIR/rpm/$RPM_ARCH/"
echo "Copied $RPM_BASENAME to rpm/$RPM_ARCH/"

# Sign the RPM package (gpgcheck=1 in repo config requires this)
cat > ~/.rpmmacros <<MACROS
%_gpg_name $GPG_KEY_ID
%__gpg_sign_cmd %{__gpg} --batch --verbose --no-armor --no-secmem-warning -u "%{_gpg_name}" -sbo %{__signature_filename} --digest-algo sha256 %{__plaintext_filename}
MACROS
rpmsign --addsign "$REPO_DIR/rpm/$RPM_ARCH/$RPM_BASENAME"

# Verify signature with rpm -K (works natively on Fedora)
gpg --armor --export "$GPG_KEY_ID" > /tmp/rpm-verify-key.asc
rpm --import /tmp/rpm-verify-key.asc
rpm -K "$REPO_DIR/rpm/$RPM_ARCH/$RPM_BASENAME" | grep -qi "signatures ok" || {
  echo "ERROR: RPM signature verification failed for $RPM_BASENAME"
  rpm -K "$REPO_DIR/rpm/$RPM_ARCH/$RPM_BASENAME"
  exit 1
}
echo "Signed and verified $RPM_BASENAME"

# Prune old versions within this arch — keep only the latest 1
cd "$REPO_DIR/rpm/$RPM_ARCH"
# shellcheck disable=SC2012
ls -t *.rpm 2>/dev/null | tail -n +2 | xargs -r rm -f
KEPT=$(ls -1 *.rpm 2>/dev/null | wc -l)
echo "Kept $KEPT .rpm file(s) in $RPM_ARCH after pruning"

# Generate repository metadata (createrepo_c handles multi-arch natively)
cd "$REPO_DIR/rpm"
createrepo_c --update .
echo "Generated repodata/ (arches: $(ls -d */ 2>/dev/null | tr -d '/' | tr '\n' ' '))"

# GPG sign repomd.xml (detached armored signature)
rm -f repodata/repomd.xml.asc
gpg --batch --yes --default-key "$GPG_KEY_ID" --detach-sign --armor \
  -o repodata/repomd.xml.asc repodata/repomd.xml
echo "Signed repodata/repomd.xml"

echo "=== RPM repository updated ==="
