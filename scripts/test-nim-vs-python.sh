#!/bin/bash
#
# Byte-for-byte parity test: apply every Python patch and every Nim patch
# to a fresh copy of the same input, then diff the pairs.
#
# Pipeline:
#   1. Extract a pristine app.asar from Claude-Setup-x64.exe (same steps as
#      build-patched-tarball.sh, but we only keep .vite/build/*.js).
#   2. Compile the Nim ports via scripts/compile-nim-patches.sh.
#   3. For each patches/*.py and patches-nim/*.nim, parse the
#      "@patch-target:" header to learn which JS file it mutates.
#   4. Copy the fresh target next to each patch, then run the patches in
#      parallel (one per CPU core) — once for Python, once for Nim.
#   5. Compare each py/<name>.js against nim/<name>.js. Emit:
#        PASS  — byte-identical and both patches exited identically
#        FAIL  — outputs differ or exit codes differ
#        WARN  — Python-only patch (no Nim port)
#        WARN  — Nim-only patch (no Python source)
#
# Exit status is zero iff every pair passed (WARNings do not fail the run).
#
# Usage: scripts/test-nim-vs-python.sh [--exe <path>]
#   Default exe: $PROJECT_DIR/Claude-Setup-x64.exe

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PATCHES_DIR="$PROJECT_DIR/patches"
NIM_DIR="$PROJECT_DIR/patches-nim"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_pass()  { echo -e "${GREEN}[PASS]${NC} $*"; }
log_fail()  { echo -e "${RED}[FAIL]${NC} $*"; }
log_step()  { echo -e "${BLUE}==>${NC} $*"; }

# ── args ────────────────────────────────────────────────────────────
EXE_PATH="$PROJECT_DIR/Claude-Setup-x64.exe"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --exe) EXE_PATH="$2"; shift 2;;
        --help|-h)
            sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
            exit 0;;
        *) log_error "Unknown argument: $1"; exit 1;;
    esac
done

if [ ! -f "$EXE_PATH" ]; then
    log_error "Exe not found: $EXE_PATH"
    log_info "Run scripts/build-local.sh once to download it, or pass --exe <path>"
    exit 1
fi

for dep in 7z asar python3 cmp; do
    command -v "$dep" >/dev/null || { log_error "Missing dependency: $dep"; exit 1; }
done

WORKDIR=$(mktemp -d -t nim-vs-py.XXXXXX)
KEEP_WORKDIR=0
cleanup() { [ "$KEEP_WORKDIR" = "0" ] && rm -rf "$WORKDIR"; }
trap cleanup EXIT

JOBS="${JOBS:-$(nproc)}"

# ── 1. extract fresh JS files ───────────────────────────────────────
log_step "Extracting pristine JS from $(basename "$EXE_PATH")"
EXTRACT_DIR="$WORKDIR/extract"
mkdir -p "$EXTRACT_DIR"
7z x -y "$EXE_PATH" -o"$EXTRACT_DIR" >/dev/null

NUPKG=$(find "$EXTRACT_DIR" -maxdepth 1 -name "AnthropicClaude-*.nupkg" | head -1)
if [ -z "$NUPKG" ]; then
    log_error "No nupkg found inside exe"
    exit 1
fi
NUPKG_DIR="$WORKDIR/nupkg"
mkdir -p "$NUPKG_DIR"
7z x -y "$NUPKG" -o"$NUPKG_DIR" >/dev/null

ASAR="$NUPKG_DIR/lib/net45/resources/app.asar"
[ -f "$ASAR" ] || { log_error "app.asar missing at $ASAR"; exit 1; }

ASAR_EXT="$WORKDIR/app.asar.contents"
asar extract "$ASAR" "$ASAR_EXT"

FRESH_DIR="$WORKDIR/fresh"
mkdir -p "$FRESH_DIR"
for js in index.js mainView.js; do
    src="$ASAR_EXT/.vite/build/$js"
    if [ -f "$src" ]; then
        cp "$src" "$FRESH_DIR/$js"
        log_info "  fresh/$js ($(wc -c < "$FRESH_DIR/$js") bytes)"
    else
        log_warn "  .vite/build/$js missing — patches targeting it will be skipped"
    fi
done

# ── 2. compile the Nim ports ────────────────────────────────────────
log_step "Compiling Nim patches"
"$SCRIPT_DIR/compile-nim-patches.sh" >/dev/null

# ── 3. enumerate patches + their targets ────────────────────────────
# Parse "@patch-target: <path>" in the first 30 lines. Mirrors the regex
# in scripts/apply_patches.py so files that declare the header inside a
# docstring (no leading '# ') are still picked up.
extract_target_filename() {
    local file="$1"
    head -n 30 "$file" \
        | sed -nE 's/.*@patch-target:[[:space:]]*([^[:space:]]+).*/\1/p' \
        | head -1 \
        | awk -F/ '{print $NF}'
}

declare -A PY_TARGETS
declare -A NIM_TARGETS

for py in "$PATCHES_DIR"/*.py; do
    [ -f "$py" ] || continue
    name=$(basename "$py" .py)
    target=$(extract_target_filename "$py")
    [ -n "$target" ] || continue
    PY_TARGETS[$name]="$target"
done

for nim in "$NIM_DIR"/*.nim; do
    [ -f "$nim" ] || continue
    name=$(basename "$nim" .nim)
    target=$(extract_target_filename "$nim")
    [ -n "$target" ] || continue
    NIM_TARGETS[$name]="$target"
done

mapfile -t ALL_NAMES < <(printf '%s\n' "${!PY_TARGETS[@]}" "${!NIM_TARGETS[@]}" | sort -u)

log_info "Patches: ${#PY_TARGETS[@]} Python, ${#NIM_TARGETS[@]} Nim (union: ${#ALL_NAMES[@]})"

# ── 4. apply patches in parallel ────────────────────────────────────
RESULTS_PY="$WORKDIR/results/py"
RESULTS_NIM="$WORKDIR/results/nim"
mkdir -p "$RESULTS_PY" "$RESULTS_NIM"

# Per-patch worker.
#   $1 kind (py|nim)
#   $2 patch name (basename without extension)
#   $3 target filename (basename of the JS file the patch mutates)
#
# Writes three files per patch in $RESULTS_*:
#   <name>.js    the patch output
#   <name>.log   stdout+stderr from the patch script
#   <name>.exit  exit code
run_patch() {
    local kind="$1" name="$2" target="$3"
    local fresh_file="$FRESH_DIR/$target"
    local out_dir="$WORKDIR/results/$kind"
    local out_js="$out_dir/$name.js"
    local out_log="$out_dir/$name.log"
    local out_exit="$out_dir/$name.exit"

    if [ ! -f "$fresh_file" ]; then
        echo "skipped — fresh/$target not extracted" > "$out_log"
        echo "254" > "$out_exit"
        return 0
    fi

    cp "$fresh_file" "$out_js"
    local rc=0
    if [ "$kind" = "py" ]; then
        python3 "$PATCHES_DIR/$name.py" "$out_js" >"$out_log" 2>&1 || rc=$?
    else
        local bin="$NIM_DIR/$name"
        if [ ! -x "$bin" ]; then
            echo "nim binary missing at $bin" > "$out_log"
            echo "253" > "$out_exit"
            return 0
        fi
        "$bin" "$out_js" >"$out_log" 2>&1 || rc=$?
    fi
    echo "$rc" > "$out_exit"
}

# Concurrency gate: limit to $JOBS background workers at a time.
sem_wait() {
    while [ "$(jobs -rp | wc -l)" -ge "$JOBS" ]; do
        wait -n 2>/dev/null || true
    done
}

run_side() {
    local kind="$1"
    local -n map_ref="$2"
    for name in "${!map_ref[@]}"; do
        sem_wait
        run_patch "$kind" "$name" "${map_ref[$name]}" &
    done
    wait
}

log_step "Running Python patches (-j$JOBS)"
py_start=$(date +%s.%N)
run_side py PY_TARGETS
py_end=$(date +%s.%N)
log_info "Python patches done in $(awk -v s="$py_start" -v e="$py_end" 'BEGIN{printf "%.2fs", e-s}')"

log_step "Running Nim patches (-j$JOBS)"
nim_start=$(date +%s.%N)
run_side nim NIM_TARGETS
nim_end=$(date +%s.%N)
log_info "Nim patches done in $(awk -v s="$nim_start" -v e="$nim_end" 'BEGIN{printf "%.2fs", e-s}')"

# ── 5. compare each pair ────────────────────────────────────────────
log_step "Comparing outputs"
pass=0
fail=0
py_only=0
nim_only=0
fail_names=()

for name in "${ALL_NAMES[@]}"; do
    have_py=0; have_nim=0
    [ -n "${PY_TARGETS[$name]:-}" ] && have_py=1
    [ -n "${NIM_TARGETS[$name]:-}" ] && have_nim=1

    py_js="$RESULTS_PY/$name.js"
    nim_js="$RESULTS_NIM/$name.js"
    py_exit=$(cat "$RESULTS_PY/$name.exit" 2>/dev/null || echo 255)
    nim_exit=$(cat "$RESULTS_NIM/$name.exit" 2>/dev/null || echo 255)

    if [ "$have_py" = 1 ] && [ "$have_nim" = 1 ]; then
        if [ "$py_exit" != "$nim_exit" ]; then
            log_fail "$name — exit codes differ (py=$py_exit nim=$nim_exit)"
            fail=$((fail + 1))
            fail_names+=("$name")
        elif cmp -s "$py_js" "$nim_js"; then
            log_pass "$name"
            pass=$((pass + 1))
        else
            size_py=$(wc -c < "$py_js")
            size_nim=$(wc -c < "$nim_js")
            log_fail "$name — outputs differ (py=${size_py}B nim=${size_nim}B)"
            fail=$((fail + 1))
            fail_names+=("$name")
        fi
    elif [ "$have_py" = 1 ]; then
        log_warn "$name — Python-only (no Nim port)"
        py_only=$((py_only + 1))
    else
        log_warn "$name — Nim-only (no Python source)"
        nim_only=$((nim_only + 1))
    fi
done

echo
echo "=============================================================="
echo "Summary"
echo "  pass:      $pass"
echo "  fail:      $fail"
echo "  py-only:   $py_only"
echo "  nim-only:  $nim_only"
echo "  total:     ${#ALL_NAMES[@]}"
echo "=============================================================="

if [ "$fail" -gt 0 ]; then
    log_error "Failing pairs: ${fail_names[*]}"
    log_info "Logs:  $WORKDIR/results/{py,nim}/<name>.log"
    log_info "Diff:  diff <(xxd $WORKDIR/results/py/<name>.js) <(xxd $WORKDIR/results/nim/<name>.js) | head"
    KEEP_WORKDIR=1
    log_info "Work dir preserved: $WORKDIR"
    exit 1
fi

log_info "All paired patches are byte-identical"
