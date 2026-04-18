#!/usr/bin/env bash
# Thin wrapper over patches/Makefile: parallel incremental build of
# every Nim patch. Called from build-patched-tarball.sh.
#
# Fallback cascade:
#   1. Native `nim` + `make` — fastest, preferred.
#   2. If the only failure is "cannot open file: regex" (the nimble regex
#      package isn't installed), run `nimble install -y regex` and retry.
#   3. If any native compile still fails, fall back to building inside the
#      official nimlang/nim Docker image.
#   4. If none of those work, error out — Nim patches are required.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
PATCHES_DIR="${1:-$REPO_DIR/patches}"

if [ ! -d "$PATCHES_DIR" ] || ! ls "$PATCHES_DIR"/*.nim &>/dev/null; then
    echo "[nim] No .nim files found in patches/ — nothing to compile"
    exit 0
fi

DOCKER_IMAGE="${NIM_DOCKER_IMAGE:-nimlang/nim:latest}"
JOBS="${JOBS:-$(nproc)}"
MAKE_ARGS=("${@:-all}")

log() { echo "[nim] $*"; }

run_make() {
    local logfile=$1
    shift
    (cd "$PATCHES_DIR" && make -j"$JOBS" "$@") >"$logfile" 2>&1
}

tail_log() {
    tail -n 40 "$1" | sed 's/^/  /'
}

is_regex_missing() {
    grep -qE "cannot open file: regex|imported module.*'regex'" "$1"
}

is_nre_missing() {
    grep -qE "cannot open file: nre|imported module.*'nre'" "$1"
}

try_native() {
    local logfile
    logfile=$(mktemp)
    if run_make "$logfile" "${MAKE_ARGS[@]}"; then
        cat "$logfile"
        rm -f "$logfile"
        return 0
    fi

    if is_regex_missing "$logfile"; then
        log "regex package missing — running 'nimble install -y regex'"
        if command -v nimble &>/dev/null && nimble install -y regex; then
            if run_make "$logfile" "${MAKE_ARGS[@]}"; then
                cat "$logfile"
                rm -f "$logfile"
                return 0
            fi
        else
            log "nimble install regex failed or nimble missing"
        fi
    fi

    log "native compile failed — log:"
    tail_log "$logfile"
    rm -f "$logfile"
    return 1
}

try_docker() {
    if ! command -v docker &>/dev/null; then
        log "docker not installed — cannot fall back"
        return 1
    fi

    log "falling back to Docker build ($DOCKER_IMAGE)"

    local uid gid
    uid=$(id -u)
    gid=$(id -g)

    docker run --rm \
        -v "$REPO_DIR:$REPO_DIR" \
        -w "$PATCHES_DIR" \
        "$DOCKER_IMAGE" \
        bash -c "set -e
            if ! command -v make >/dev/null; then
                apt-get update -qq
                DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
                    make
            fi
            nimble install -y regex 2>&1 || true
            make -j$JOBS ${MAKE_ARGS[*]}
            chown -R $uid:$gid . || true"
}

if command -v nim &>/dev/null; then
    if try_native; then
        exit 0
    fi
else
    log "nim not installed — skipping native build"
fi

if try_docker; then
    exit 0
fi

log "[ERROR] No working Nim toolchain — cannot compile patches"
exit 1
