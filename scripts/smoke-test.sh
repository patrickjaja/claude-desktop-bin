#!/bin/bash
#
# Electron smoke test - verifies the patched app doesn't crash on startup.
#
# The binary is launched directly with no app argument: Electron auto-loads the
# exe-adjacent resources/app.asar (the OnlyLoadAppFromAsar fuse in the official
# build permits nothing else).
#
# Usage: ./scripts/smoke-test.sh <electron_binary>
# Exit:  0=pass, 1=crash/error, 2=missing deps
#
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ELECTRON_BIN="$1"
TIMEOUT_SECONDS=15
STDERR_LOG=$(mktemp)
trap "rm -f $STDERR_LOG" EXIT

if [ -z "$ELECTRON_BIN" ]; then
    echo "Usage: $0 <electron_binary>"
    exit 2
fi

if [ ! -x "$ELECTRON_BIN" ]; then
    echo -e "${RED}[FAIL]${NC} Electron binary not found or not executable: $ELECTRON_BIN"
    exit 2
fi

APP_ASAR="$(dirname "$ELECTRON_BIN")/resources/app.asar"
if [ ! -f "$APP_ASAR" ]; then
    echo -e "${RED}[FAIL]${NC} exe-adjacent resources/app.asar not found: $APP_ASAR"
    exit 2
fi

if ! command -v xvfb-run &>/dev/null; then
    echo -e "${RED}[FAIL]${NC} xvfb-run not found (install xorg-server-xvfb)"
    exit 2
fi

echo "Starting Electron smoke test..."
echo "  electron: $ELECTRON_BIN"
echo "  app.asar: $APP_ASAR (auto-loaded)"
echo "  timeout:  ${TIMEOUT_SECONDS}s"

# Verify chrome-sandbox permissions (SUID root required for sandbox to work)
# Skip with SKIP_SANDBOX_CHECK=1 (e.g. for extracted AppImages where SUID can't be preserved)
ELECTRON_DIR="$(dirname "$ELECTRON_BIN")"
SANDBOX_BIN="$ELECTRON_DIR/chrome-sandbox"
if [ "${SKIP_SANDBOX_CHECK:-0}" = "1" ]; then
    echo -e "${YELLOW}[SKIP]${NC} chrome-sandbox permission check (SKIP_SANDBOX_CHECK=1)"
elif [ -f "$SANDBOX_BIN" ]; then
    SANDBOX_PERMS=$(stat -c '%a' "$SANDBOX_BIN" 2>/dev/null || stat -f '%Lp' "$SANDBOX_BIN" 2>/dev/null)
    SANDBOX_OWNER=$(stat -c '%U' "$SANDBOX_BIN" 2>/dev/null || stat -f '%Su' "$SANDBOX_BIN" 2>/dev/null)
    if [ "$SANDBOX_PERMS" != "4755" ]; then
        echo -e "${RED}[FAIL]${NC} chrome-sandbox has mode $SANDBOX_PERMS (expected 4755)"
        echo "  Fix: chmod 4755 $SANDBOX_BIN"
        exit 1
    fi
    if [ "$SANDBOX_OWNER" != "root" ]; then
        echo -e "${RED}[FAIL]${NC} chrome-sandbox owned by $SANDBOX_OWNER (expected root)"
        echo "  Fix: chown root:root $SANDBOX_BIN"
        exit 1
    fi
    echo -e "${GREEN}[OK]${NC} chrome-sandbox permissions correct (4755, root)"
else
    echo -e "${YELLOW}[SKIP]${NC} chrome-sandbox not found at $SANDBOX_BIN (system electron?)"
fi

# Start the app in a virtual framebuffer (no app argument: Electron auto-loads
# the exe-adjacent resources/app.asar). Isolated user-data-dir so the test never
# touches a real profile. setsid gives the whole xvfb-run/Electron tree its own
# process group so the kill below reaps every child - killing only xvfb-run
# leaves orphaned Electron processes holding stdout/stderr open.
SMOKE_USERDATA=$(mktemp -d)
trap "rm -f $STDERR_LOG; rm -rf $SMOKE_USERDATA" EXIT
setsid xvfb-run --auto-servernum --server-args="-screen 0 1280x720x24" \
    "$ELECTRON_BIN" --no-sandbox --user-data-dir="$SMOKE_USERDATA" 2>"$STDERR_LOG" &
APP_PID=$!
_kill_app_tree() { kill -- "-$APP_PID" 2>/dev/null || kill "$APP_PID" 2>/dev/null || true; }

# Poll every second — fail if process dies early
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT_SECONDS ]; do
    if ! kill -0 "$APP_PID" 2>/dev/null; then
        EXIT_CODE=0; wait "$APP_PID" 2>/dev/null || EXIT_CODE=$?
        echo -e "${RED}[FAIL]${NC} App crashed after ${ELAPSED}s (exit code: $EXIT_CODE)"
        echo "--- stderr output ---"
        cat "$STDERR_LOG"
        echo "---"
        exit 1
    fi
    sleep 1
    ELAPSED=$((ELAPSED + 1))
done

# Check stderr for JS runtime errors.
ERROR_PATTERN='(TypeError|ReferenceError|SyntaxError|Cannot read properties|ENOENT)'
ERRORS=$(grep -E "$ERROR_PATTERN" "$STDERR_LOG" || true)
if [ -n "$ERRORS" ]; then
    echo -e "${RED}[FAIL]${NC} Runtime JS errors detected:"
    echo "$ERRORS"
    _kill_app_tree; wait "$APP_PID" 2>/dev/null || true
    exit 1
fi

_kill_app_tree; wait "$APP_PID" 2>/dev/null || true
echo -e "${GREEN}[PASS]${NC} Smoke test passed — app survived ${TIMEOUT_SECONDS}s"
exit 0
