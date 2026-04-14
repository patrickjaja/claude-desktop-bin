#!/bin/bash
#
# Rebuild node-pty for a target architecture inside a pre-patched tarball
#
# The tarball from build-patched-tarball.sh ships an x86_64 pty.node.
# For ARM64 packages (deb, rpm, appimage), we need a native arm64 pty.node.
# This script replaces the pty.node in-place using Docker + QEMU when
# the target arch differs from the host.
#
# Usage: ./scripts/rebuild-pty-for-arch.sh --arch arm64 <tarball_path>
#
# Requirements:
#   - node, npm (for extracting version info from asar)
#   - docker + QEMU binfmt registered (for cross-arch builds)
#   - file (for ELF verification)
#
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Parse --arch flag
TARGET_ARCH=""
if [ "${1:-}" = "--arch" ]; then
    TARGET_ARCH="${2:-}"
    shift 2
fi

TARBALL_PATH="${1:-}"

if [ -z "$TARGET_ARCH" ] || [ -z "$TARBALL_PATH" ]; then
    echo "Usage: $0 --arch <arm64|x64> <tarball_path>"
    echo ""
    echo "Rebuilds node-pty inside the tarball for the target architecture."
    echo "The tarball is modified in-place."
    echo ""
    echo "Architectures:"
    echo "  arm64, aarch64  — 64-bit ARM (Raspberry Pi 5, NVIDIA Jetson, DGX Spark)"
    echo "  x64, amd64      — 64-bit x86 (default build target)"
    exit 1
fi

if [ ! -f "$TARBALL_PATH" ]; then
    log_error "Tarball not found: $TARBALL_PATH"
    exit 1
fi

# Normalize arch names
case "$TARGET_ARCH" in
    arm64|aarch64)  ELECTRON_ARCH="arm64"; DOCKER_PLATFORM="linux/arm64" ;;
    x64|amd64|x86_64) ELECTRON_ARCH="x64"; DOCKER_PLATFORM="linux/amd64" ;;
    *)
        log_error "Unsupported architecture: $TARGET_ARCH (supported: arm64, aarch64, x64, amd64)"
        exit 1
        ;;
esac

# Determine if we need Docker for cross-compilation
HOST_ARCH=$(uname -m)
NEEDS_DOCKER=false
if [ "$HOST_ARCH" = "x86_64" ] && [ "$ELECTRON_ARCH" = "arm64" ]; then
    NEEDS_DOCKER=true
elif [ "$HOST_ARCH" = "aarch64" ] && [ "$ELECTRON_ARCH" = "x64" ]; then
    NEEDS_DOCKER=true
fi

log_info "Rebuilding node-pty for $ELECTRON_ARCH (host: $HOST_ARCH, docker: $NEEDS_DOCKER)"

# Extract tarball
REPACK_DIR=$(mktemp -d)
tar xzf "$TARBALL_PATH" -C "$REPACK_DIR"

# Check node-pty exists in the tarball
PTY_DIR="$REPACK_DIR/app/app.asar.unpacked/node_modules/node-pty"
PTY_NODE="$PTY_DIR/build/Release/pty.node"
if [ ! -d "$PTY_DIR" ]; then
    log_warn "node-pty not found in tarball — nothing to rebuild"
    rm -rf "$REPACK_DIR"
    exit 0
fi

# Extract version info from the asar
log_info "Reading version info from app.asar..."
ASAR_TMP="$REPACK_DIR/_asar_tmp"
npx --yes @electron/asar extract "$REPACK_DIR/app/app.asar" "$ASAR_TMP" 2>/dev/null

ELECTRON_VERSION=$(node -e "console.log(require('$ASAR_TMP/package.json').devDependencies?.electron || '')" 2>/dev/null)
NODE_PTY_VERSION=$(node -e "console.log(require('$ASAR_TMP/package.json').optionalDependencies?.['node-pty'] || '')" 2>/dev/null)
rm -rf "$ASAR_TMP"

if [ -z "$ELECTRON_VERSION" ] || [ -z "$NODE_PTY_VERSION" ]; then
    log_error "Could not detect Electron ($ELECTRON_VERSION) or node-pty ($NODE_PTY_VERSION) version"
    rm -rf "$REPACK_DIR"
    exit 1
fi

log_info "node-pty@$NODE_PTY_VERSION / Electron $ELECTRON_VERSION"

# Rebuild node-pty
PTY_OUTPUT_DIR=$(mktemp -d)

if [ "$NEEDS_DOCKER" = true ]; then
    log_info "Cross-compiling via Docker ($DOCKER_PLATFORM, node:20-bullseye)..."
    docker run --rm --platform "$DOCKER_PLATFORM" \
        -v "$PTY_OUTPUT_DIR:/output" \
        node:20-bullseye \
        bash -c "
            set -e
            cd /tmp
            npm init -y > /dev/null 2>&1
            npm install 'node-pty@$NODE_PTY_VERSION' --ignore-scripts 2>&1 | tail -1
            npx @electron/rebuild --version '$ELECTRON_VERSION' \
                --module-dir node_modules/node-pty --arch $ELECTRON_ARCH 2>&1 | tail -3
            cp node_modules/node-pty/build/Release/pty.node /output/pty.node
        "
else
    log_info "Native compilation..."
    (
        BUILD_DIR=$(mktemp -d)
        cd "$BUILD_DIR"
        npm init -y > /dev/null 2>&1
        npm install "node-pty@$NODE_PTY_VERSION" --ignore-scripts 2>&1 | tail -1
        npx @electron/rebuild --version "$ELECTRON_VERSION" \
            --module-dir node_modules/node-pty --arch "$ELECTRON_ARCH" 2>&1 | tail -3
        cp node_modules/node-pty/build/Release/pty.node "$PTY_OUTPUT_DIR/pty.node"
        rm -rf "$BUILD_DIR"
    )
fi

# Verify and install rebuilt pty.node
REBUILT_PTY="$PTY_OUTPUT_DIR/pty.node"
if [ ! -f "$REBUILT_PTY" ] || ! file "$REBUILT_PTY" | grep -q "ELF"; then
    log_error "node-pty rebuild failed — no valid ELF binary produced"
    rm -rf "$REPACK_DIR" "$PTY_OUTPUT_DIR"
    exit 1
fi

# Verify correct architecture
if [ "$ELECTRON_ARCH" = "arm64" ]; then
    if ! file "$REBUILT_PTY" | grep -qi "aarch64\|ARM aarch64"; then
        log_error "Built pty.node is not ARM64: $(file -b "$REBUILT_PTY")"
        rm -rf "$REPACK_DIR" "$PTY_OUTPUT_DIR"
        exit 1
    fi
elif [ "$ELECTRON_ARCH" = "x64" ]; then
    if ! file "$REBUILT_PTY" | grep -q "x86-64"; then
        log_error "Built pty.node is not x86-64: $(file -b "$REBUILT_PTY")"
        rm -rf "$REPACK_DIR" "$PTY_OUTPUT_DIR"
        exit 1
    fi
fi

# Replace in tarball
rm -f "$PTY_NODE"
rm -f "$PTY_DIR/build/Release/"*.exe "$PTY_DIR/build/Release/"*.dll
mkdir -p "$PTY_DIR/build/Release"
cp "$REBUILT_PTY" "$PTY_NODE"
log_info "Installed pty.node: $(file -b "$PTY_NODE" | cut -d, -f1-2)"

# Repack tarball in-place
TARBALL_ABS=$(cd "$(dirname "$TARBALL_PATH")" && pwd)/$(basename "$TARBALL_PATH")
cd "$REPACK_DIR"
tar -czf "$TARBALL_ABS" app/ icons/ launcher/
cd /
rm -rf "$REPACK_DIR" "$PTY_OUTPUT_DIR"

log_info "Tarball repacked with $ELECTRON_ARCH node-pty: $TARBALL_ABS"
