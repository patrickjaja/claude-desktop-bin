#!/bin/bash
#
# Electron smoke test - verifies the patched app doesn't crash on startup
#
# Usage: ./scripts/smoke-test.sh <app.asar_path> [electron_binary]
# Exit:  0=pass, 1=crash/error, 2=missing deps
#
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

APP_ASAR="$1"
ELECTRON_BIN="${2:-electron}"
TIMEOUT_SECONDS=15
STDERR_LOG=$(mktemp)
trap "rm -f $STDERR_LOG" EXIT

if [ -z "$APP_ASAR" ]; then
    echo "Usage: $0 <app.asar_path> [electron_binary]"
    exit 2
fi

if [ ! -f "$APP_ASAR" ]; then
    echo -e "${RED}[FAIL]${NC} app.asar not found: $APP_ASAR"
    exit 2
fi

if ! command -v "$ELECTRON_BIN" &>/dev/null; then
    echo -e "${RED}[FAIL]${NC} Electron binary not found: $ELECTRON_BIN"
    exit 2
fi

if ! command -v xvfb-run &>/dev/null; then
    echo -e "${RED}[FAIL]${NC} xvfb-run not found (install xorg-server-xvfb)"
    exit 2
fi

echo "Starting Electron smoke test..."
echo "  app.asar: $APP_ASAR"
echo "  electron: $(command -v "$ELECTRON_BIN")"
echo "  timeout:  ${TIMEOUT_SECONDS}s"

# Verify chrome-sandbox permissions (SUID root required for sandbox to work)
# Skip with SKIP_SANDBOX_CHECK=1 (e.g. for extracted AppImages where SUID can't be preserved)
ELECTRON_DIR="$(dirname "$(command -v "$ELECTRON_BIN")")"
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

# Start the app in a virtual framebuffer
xvfb-run --auto-servernum --server-args="-screen 0 1280x720x24" \
    "$ELECTRON_BIN" "$APP_ASAR" --no-sandbox 2>"$STDERR_LOG" &
APP_PID=$!

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

# Check stderr for JS runtime errors
if grep -qE "(TypeError|ReferenceError|SyntaxError|Cannot read properties|ENOENT)" "$STDERR_LOG"; then
    echo -e "${RED}[FAIL]${NC} Runtime JS errors detected:"
    grep -E "(TypeError|ReferenceError|SyntaxError|Cannot read properties|ENOENT)" "$STDERR_LOG"
    kill "$APP_PID" 2>/dev/null; wait "$APP_PID" 2>/dev/null || true
    exit 1
fi

kill "$APP_PID" 2>/dev/null; wait "$APP_PID" 2>/dev/null || true
echo -e "${GREEN}[PASS]${NC} Smoke test passed — app survived ${TIMEOUT_SECONDS}s"
exit 0
