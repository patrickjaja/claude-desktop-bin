#!/usr/bin/env bash
#
# apt-fetch-verify.sh - Single source of truth for querying Anthropic's official
# Linux .deb apt repository, GPG-verifying it, and resolving the highest version
# per architecture. Shared by both .github/workflows/version-check.yml (poll only)
# and .github/workflows/build-and-release.yml (poll + download .deb artifacts).
#
# It replaces the old Windows-MSIX ingest path: instead of polling
# downloads.claude.ai/releases/win32/x64/.latest and self-managing Electron, we
# ingest the official Linux .deb that Anthropic publishes and signs.
#
# Trust model:
#   1. The apt `Release` index is signed (detached `Release.gpg`) by Anthropic's
#      release key, fingerprint 31DD DE24 DDFA B679 F42D 7BD2 BAA9 29FF 1A7E CACE.
#   2. We verify that signature against a public key committed to this repo
#      (packaging/claude-desktop-archive-keyring.asc - the SAME key the build
#      script uses, single source of truth). The committed key is the trust
#      anchor, NOT a key fetched at runtime (a keyserver MITM/outage can't weaken
#      us). A keyserver fetch is only a last-resort fallback if the file is gone.
#   3. The signed `Release` pins the SHA256 of each `Packages` index; we verify
#      the downloaded Packages against it. So a verified Release transitively
#      authenticates Packages, which in turn carries the per-.deb SHA256.
#   4. When downloading a .deb, we verify its SHA256 against the (now-trusted)
#      Packages entry.
#
# Subcommands:
#   poll               Print the highest version across amd64+arm64 (GPG-verified).
#                      Output (stdout): a single line "VERSION".
#   resolve <arch>     Print "VERSION<TAB>FILENAME<TAB>SHA256" for the highest
#                      version of the given arch (amd64|arm64). GPG-verified.
#   download <arch> <out-dir>
#                      Resolve highest <arch>, download the .deb into <out-dir>,
#                      verify its SHA256. Prints the resolved metadata to stderr
#                      and writes <out-dir>/claude-desktop_<arch>.meta with
#                      VERSION=, FILENAME=, SHA256=, DEB_PATH= for the caller.
#
# Environment:
#   CLAUDE_DESKTOP_APT_BASE   apt repo base (default below). The dists/ and pool/
#                             trees hang off this. Override for testing/mirrors.
#   ANTHROPIC_APT_KEY         path to the armored public key (default: the
#                             committed packaging/claude-desktop-archive-keyring.asc
#                             resolved relative to this script).
#   APT_KEY_FALLBACK_KEYSERVER  if set to "1", and the committed key file is
#                             missing, fetch the key from keyserver.ubuntu.com by
#                             fingerprint as a last resort (off by default).
#
set -euo pipefail

APT_BASE="${CLAUDE_DESKTOP_APT_BASE:-https://downloads.claude.ai/claude-desktop/apt/stable}"
DISTS="${APT_BASE}/dists/stable"
KEY_FPR="31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE"

# Resolve the repo root from this script's location (.github/scripts/), then
# point at the canonical Anthropic signing key the build script also bundles.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DEFAULT_KEY="${REPO_ROOT}/packaging/claude-desktop-archive-keyring.asc"
KEY_FILE="${ANTHROPIC_APT_KEY:-$DEFAULT_KEY}"

log() { echo "$@" >&2; }
die() { echo "::error::$*" >&2; exit 1; }

# curl with retries; $1=url $2=out-file ("-" for stdout)
fetch() {
  local url="$1" out="$2"
  curl -fsSL --retry 4 --retry-delay 5 --max-time 120 -o "$out" "$url" \
    || die "failed to download ${url}"
}

# Import the Anthropic release key into a throwaway GNUPGHOME and echo its path.
# The committed key file is the trust anchor; keyserver is opt-in fallback only.
setup_keyring() {
  local gnupg
  gnupg="$(mktemp -d)"
  chmod 700 "$gnupg"
  export GNUPGHOME="$gnupg"
  if [ -f "$KEY_FILE" ]; then
    gpg --batch --quiet --import "$KEY_FILE" \
      || die "failed to import committed apt key ${KEY_FILE}"
  elif [ "${APT_KEY_FALLBACK_KEYSERVER:-0}" = "1" ]; then
    log "::warning::committed key ${KEY_FILE} missing - falling back to keyserver"
    gpg --batch --quiet --keyserver hkps://keyserver.ubuntu.com \
        --recv-keys "$KEY_FPR" \
      || die "failed to fetch apt key ${KEY_FPR} from keyserver"
  else
    die "apt signing key not found at ${KEY_FILE} (set APT_KEY_FALLBACK_KEYSERVER=1 to use a keyserver)"
  fi
  # Assert the exact fingerprint is present - guards against a swapped key file.
  gpg --batch --with-colons --fingerprint 2>/dev/null \
    | grep -q "^fpr:::::::::${KEY_FPR}:" \
    || die "imported apt key fingerprint != expected ${KEY_FPR}"
  echo "$gnupg"
}

# Download + GPG-verify Release, then download + checksum-verify the per-arch
# Packages index. Echoes the path to the verified Packages file on stdout.
# $1 = arch (amd64|arm64)
verified_packages() {
  local arch="$1" work
  work="$(mktemp -d)"
  local gnupg; gnupg="$(setup_keyring)"

  fetch "${DISTS}/Release"     "${work}/Release"
  fetch "${DISTS}/Release.gpg" "${work}/Release.gpg"

  GNUPGHOME="$gnupg" gpg --batch --verify "${work}/Release.gpg" "${work}/Release" \
    >/dev/null 2>&1 \
    || die "GPG verification of apt Release FAILED - refusing to trust repo"
  log "[verify] apt Release GPG signature OK (key ${KEY_FPR})"

  fetch "${DISTS}/main/binary-${arch}/Packages" "${work}/Packages"

  # The signed Release pins the SHA256 of each Packages file. Verify it so a
  # tampered Packages (even over HTTPS) can't inject a poisoned .deb entry.
  # Release lists checksums as: "<hash>  <size>  <path>" under a "SHA256:"
  # header, one block per algorithm. Only read lines inside the SHA256 block
  # (stop at the next "<ALG>:" header) and match the path in the 3rd field.
  local rel="main/binary-${arch}/Packages"
  local claimed actual
  claimed="$(awk '
    /^[A-Za-z0-9-]+:$/ { f = ($0 == "SHA256:"); next }
    f && $3 == "'"$rel"'" { print $1; exit }
  ' "${work}/Release")"
  actual="$(sha256sum "${work}/Packages" | cut -d' ' -f1)"
  [ -n "$claimed" ] || die "Release does not list SHA256 for ${rel}"
  [ "$claimed" = "$actual" ] \
    || die "Packages SHA256 mismatch for ${arch}: Release=${claimed} actual=${actual}"
  log "[verify] ${arch} Packages SHA256 matches signed Release"

  rm -rf "$gnupg"
  echo "${work}/Packages"
}

# Parse a Packages file, print "VERSION<TAB>FILENAME<TAB>SHA256" for the stanza
# with the highest Debian version. $1 = path to Packages.
highest_stanza() {
  python3 - "$1" <<'PY'
import re, sys
data = open(sys.argv[1], encoding="utf-8").read()
best = None
for stanza in re.split(r"\n\n+", data.strip()):
    v = re.search(r"^Version:\s*(.+)$", stanza, re.M)
    if not v:
        continue
    ver = v.group(1).strip()
    f = re.search(r"^Filename:\s*(.+)$", stanza, re.M)
    h = re.search(r"^SHA256:\s*(.+)$", stanza, re.M)
    # Compare on the numeric upstream part (strip any -debrevision); pad so
    # 1.9 < 1.10 sorts correctly.
    base = ver.split("-")[0]
    key = tuple(int(x) for x in re.findall(r"\d+", base))
    rec = (key, ver, f.group(1).strip() if f else "", h.group(1).strip() if h else "")
    if best is None or rec[0] > best[0]:
        best = rec
if best is None:
    sys.exit("no Version stanza found in Packages")
print(f"{best[1]}\t{best[2]}\t{best[3]}")
PY
}

cmd_resolve() {
  local arch="${1:?usage: resolve <amd64|arm64>}"
  local pkgs; pkgs="$(verified_packages "$arch")"
  highest_stanza "$pkgs"
}

cmd_poll() {
  # Highest version across BOTH arches (they normally match, but never assume).
  local amd arm
  amd="$(cmd_resolve amd64 | cut -f1)"
  arm="$(cmd_resolve arm64 | cut -f1)"
  python3 - "$amd" "$arm" <<'PY'
import re, sys
def key(v): return tuple(int(x) for x in re.findall(r"\d+", v.split("-")[0]))
cands = [v for v in sys.argv[1:] if v]
print(max(cands, key=key))
PY
}

cmd_download() {
  local arch="${1:?usage: download <amd64|arm64> <out-dir>}"
  local out="${2:?usage: download <amd64|arm64> <out-dir>}"
  mkdir -p "$out"
  local line ver filename sha
  line="$(cmd_resolve "$arch")"
  ver="$(echo "$line" | cut -f1)"
  filename="$(echo "$line" | cut -f2)"
  sha="$(echo "$line" | cut -f3)"
  [ -n "$filename" ] || die "no Filename for ${arch} v${ver}"
  [ -n "$sha" ] || die "no SHA256 for ${arch} v${ver}"

  local deb="${out}/$(basename "$filename")"
  log "[download] ${arch} v${ver} -> ${deb}"
  fetch "${APT_BASE}/${filename}" "$deb"

  local got; got="$(sha256sum "$deb" | cut -d' ' -f1)"
  [ "$got" = "$sha" ] \
    || die ".deb SHA256 mismatch for ${arch}: Packages=${sha} downloaded=${got}"
  log "[verify] ${arch} .deb SHA256 matches signed Packages entry"

  cat > "${out}/claude-desktop_${arch}.meta" <<META
VERSION=${ver}
FILENAME=${filename}
SHA256=${sha}
DEB_PATH=${deb}
META
  echo "$deb"
}

case "${1:-}" in
  poll)     shift; cmd_poll "$@" ;;
  resolve)  shift; cmd_resolve "$@" ;;
  download) shift; cmd_download "$@" ;;
  *) die "usage: $0 {poll|resolve <arch>|download <arch> <out-dir>}" ;;
esac
