# Maintainer: patrickjaja <patrickjajaa@gmail.com>
# Contributor: Claude Desktop Linux Community
# AUR Package Repository: https://github.com/patrickjaja/claude-desktop-bin

pkgname=claude-desktop-bin
pkgver=1.0.1217
pkgrel=1
pkgdesc="Claude AI Desktop Application (Official Binary - Linux Compatible)"
arch=('x86_64')
url="https://claude.ai"
license=('custom:Claude')
depends=('electron' 'nodejs')
makedepends=('p7zip' 'wget' 'asar' 'python')
optdepends=('claude-code: Claude Code CLI for agentic coding features (npm i -g @anthropic-ai/claude-code)')
provides=('claude-desktop')
conflicts=('claude-desktop')
source_x86_64=("Claude-Setup-x64-${pkgver}.exe::https://downloads.claude.ai/releases/win32/x64/1.0.1217/Claude-0cb4a3120aa28421aeb48e8c54f5adf8414ab411.exe")
sha256sums_x86_64=('6da48ea20930934c1c1bd52666de0c1458fea2fb7089d3d0b479ac527b140880')
options=('!strip')

prepare() {
    cd "$srcdir"

    # Extract the Windows installer
    7z x -y "Claude-Setup-x64-${pkgver}.exe" -o"extract" >/dev/null 2>&1

    # Extract the nupkg
    cd extract
    local nupkg=$(find . -maxdepth 1 -name "AnthropicClaude-*.nupkg" | head -1)
    7z x -y "$nupkg" >/dev/null 2>&1
}

build() {
    cd "$srcdir/extract"

    # Prepare app directory
    mkdir -p "$srcdir/app"
    cp "lib/net45/resources/app.asar" "$srcdir/app/"
    cp -r "lib/net45/resources/app.asar.unpacked" "$srcdir/app/" 2>/dev/null || true

    # Extract and patch app.asar
    cd "$srcdir/app"
    asar extract app.asar app.asar.contents

    # Copy i18n files into app.asar contents before repacking
    echo "Looking for i18n files..."
    mkdir -p app.asar.contents/resources/i18n
    if ls "$srcdir/extract/lib/net45/resources/"*.json 1> /dev/null 2>&1; then
        echo "Found JSON files, copying to app.asar.contents/resources/i18n/"
        cp "$srcdir/extract/lib/net45/resources/"*.json app.asar.contents/resources/i18n/
        # List what we copied for debugging
        ls -la app.asar.contents/resources/i18n/
    else
        echo "Warning: No JSON files found in lib/net45/resources/"
    fi

    # Apply all patches (embedded by generate-pkgbuild.sh)
    # Applying patch: claude-native.js
    echo "Applying patch: claude-native.js..."
    mkdir -p "app.asar.contents/node_modules/claude-native"
    cat > "app.asar.contents/node_modules/claude-native/index.js" << 'claude_native_js_EOF'
// @patch-target: app.asar.contents/node_modules/claude-native/index.js
// @patch-type: replace
/**
 * Linux-compatible native module for Claude Desktop.
 *
 * The official Claude Desktop uses @anthropic/claude-native which contains
 * Windows-specific native bindings. This module provides Linux-compatible
 * stubs and implementations using Electron APIs.
 */

const { app, Tray, Menu, nativeImage, Notification } = require('electron');
const path = require('path');

const KeyboardKey = {
    Backspace: 43, Tab: 280, Enter: 261, Shift: 272, Control: 61,
    Alt: 40, CapsLock: 56, Escape: 85, Space: 276, PageUp: 251,
    PageDown: 250, End: 83, Home: 154, LeftArrow: 175, UpArrow: 282,
    RightArrow: 262, DownArrow: 81, Delete: 79, Meta: 187
};
Object.freeze(KeyboardKey);

let tray = null;

function createTray() {
    if (tray) return tray;
    try {
        const iconPath = path.join(process.resourcesPath || __dirname, 'tray-icon.png');
        if (require('fs').existsSync(iconPath)) {
            tray = new Tray(nativeImage.createFromPath(iconPath));
            tray.setToolTip('Claude Desktop');
            const menu = Menu.buildFromTemplate([
                { label: 'Show', click: () => app.focus() },
                { type: 'separator' },
                { label: 'Quit', click: () => app.quit() }
            ]);
            tray.setContextMenu(menu);
        }
    } catch (e) {
        console.warn('Tray creation failed:', e);
    }
    return tray;
}

module.exports = {
    getWindowsVersion: () => "10.0.0",
    setWindowEffect: () => {},
    removeWindowEffect: () => {},
    getIsMaximized: () => false,
    flashFrame: () => {},
    clearFlashFrame: () => {},
    showNotification: (title, body) => {
        if (Notification.isSupported()) {
            new Notification({ title, body }).show();
        }
    },
    setProgressBar: () => {},
    clearProgressBar: () => {},
    setOverlayIcon: () => {},
    clearOverlayIcon: () => {},
    createTray,
    getTray: () => tray,
    KeyboardKey
};
claude_native_js_EOF

    # Applying patch: fix_claude_code.py
    echo "Applying patch: fix_claude_code.py..."
    python3 - "app.asar.contents/.vite/build/index.js" << 'fix_claude_code_py_EOF'
#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Patch Claude Desktop to use system-installed Claude Code on Linux.

The official Claude Desktop app only supports downloading Claude Code for
macOS and Windows. This patch modifies the app to detect and use a
system-installed Claude Code binary (/usr/bin/claude) on Linux.

Usage: python3 fix_claude_code.py <path_to_index.js>
"""

import sys
import os


def patch_claude_code(filepath):
    """Patch the Claude Code downloader to use system binary on Linux."""

    print(f"Patching Claude Code support in: {filepath}")

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content
    patches_applied = 0

    # Patch 1: getBinaryPathIfReady() - Check /usr/bin/claude first on Linux
    # Original: async getBinaryPathIfReady(){return await this.binaryExists(this.requiredVersion)?this.getBinaryPath(this.requiredVersion):null}
    old_binary_ready = b'async getBinaryPathIfReady(){return await this.binaryExists(this.requiredVersion)?this.getBinaryPath(this.requiredVersion):null}'
    new_binary_ready = b'async getBinaryPathIfReady(){console.log("[ClaudeCode] getBinaryPathIfReady called, platform:",process.platform);if(process.platform==="linux"){try{const fs=require("fs");const exists=fs.existsSync("/usr/bin/claude");console.log("[ClaudeCode] /usr/bin/claude exists:",exists);if(exists)return"/usr/bin/claude"}catch(e){console.log("[ClaudeCode] error checking /usr/bin/claude:",e)}}return await this.binaryExists(this.requiredVersion)?this.getBinaryPath(this.requiredVersion):null}'

    if old_binary_ready in content:
        content = content.replace(old_binary_ready, new_binary_ready)
        patches_applied += 1
        print("  ✓ getBinaryPathIfReady() patched")
    else:
        print("  ⚠ getBinaryPathIfReady() pattern not found")

    # Patch 2: getStatus() - Return Ready if system binary exists on Linux
    old_status = b'async getStatus(){if(await this.binaryExists(this.requiredVersion))'
    new_status = b'async getStatus(){console.log("[ClaudeCode] getStatus called, platform:",process.platform);if(process.platform==="linux"){try{const fs=require("fs");const exists=fs.existsSync("/usr/bin/claude");console.log("[ClaudeCode] /usr/bin/claude exists:",exists);if(exists){console.log("[ClaudeCode] returning Ready");return Rv.Ready}}catch(e){console.log("[ClaudeCode] error:",e)}}if(await this.binaryExists(this.requiredVersion))'

    if old_status in content:
        content = content.replace(old_status, new_status)
        patches_applied += 1
        print("  ✓ getStatus() patched")
    else:
        print("  ⚠ getStatus() pattern not found")

    # Write back if changed
    if content != original_content:
        with open(filepath, 'wb') as f:
            f.write(content)
        print(f"Claude Code patches applied: {patches_applied}/2")
        return True
    else:
        print("Warning: No Claude Code patches applied")
        return False


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    filepath = sys.argv[1]
    if not os.path.exists(filepath):
        print(f"Error: File not found: {filepath}")
        sys.exit(1)

    success = patch_claude_code(filepath)
    sys.exit(0 if success else 1)
fix_claude_code_py_EOF

    # Applying patch: fix_locale_paths.py
    echo "Applying patch: fix_locale_paths.py..."
    python3 - "app.asar.contents/.vite/build/index.js" << 'fix_locale_paths_py_EOF'
#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Patch Claude Desktop locale file paths for Linux.

The official Claude Desktop expects locale files in Electron's resourcesPath,
but on Linux with system Electron, we need to redirect to our install location.

Usage: python3 fix_locale_paths.py <path_to_index.js>
"""

import sys
import os
import re


def patch_locale_paths(filepath):
    """Patch locale file paths to use Linux install location."""

    print(f"Patching locale paths in: {filepath}")

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content
    patches_applied = 0

    # Replace process.resourcesPath with our locale path
    old_resource_path = b'process.resourcesPath'
    new_resource_path = b'"/usr/lib/claude-desktop-bin/locales"'

    if old_resource_path in content:
        count = content.count(old_resource_path)
        content = content.replace(old_resource_path, new_resource_path)
        patches_applied += count
        print(f"  Replaced process.resourcesPath: {count} occurrence(s)")

    # Also replace any hardcoded electron paths
    pattern = rb'/usr/lib/electron\d+/resources'
    replacement = b'/usr/lib/claude-desktop-bin/locales'
    content, count = re.subn(pattern, replacement, content)
    if count > 0:
        patches_applied += count
        print(f"  Replaced hardcoded electron paths: {count} occurrence(s)")

    if content != original_content:
        with open(filepath, 'wb') as f:
            f.write(content)
        print(f"Locale path patches applied: {patches_applied} total")
        return True
    else:
        print("Warning: No locale path changes made")
        return False


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    filepath = sys.argv[1]
    if not os.path.exists(filepath):
        print(f"Error: File not found: {filepath}")
        sys.exit(1)

    success = patch_locale_paths(filepath)
    sys.exit(0 if success else 1)
fix_locale_paths_py_EOF

    # Applying patch: fix_title_bar.py
    echo "Applying patch: fix_title_bar.py..."
    local target_file=$(find app.asar.contents/.vite/renderer/main_window/assets -name "MainWindowPage-*.js" 2>/dev/null | head -1)
    if [ -n "$target_file" ]; then
        python3 - "$target_file" << 'fix_title_bar_py_EOF'
#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/renderer/main_window/assets/MainWindowPage-*.js
# @patch-type: python
"""
Patch Claude Desktop title bar detection issue on Linux.

The original code has a negated condition that causes issues on Linux.
This patch fixes: if(!var1 && var2) -> if(var1 && var2)

Usage: python3 fix_title_bar.py <path_to_MainWindowPage-*.js>
"""

import sys
import os
import re


def patch_title_bar(filepath):
    """Patch the title bar detection logic."""

    print(f"Patching title bar in: {filepath}")

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content

    # Fix: if(!B&&e) -> if(B&&e) - removes the negation
    # The title bar check has a negated condition that fails on Linux
    # Pattern: if(!X&&Y) where X and Y are variable names (minified, no spaces)
    pattern = rb'if\(!([a-zA-Z_][a-zA-Z0-9_]*)\s*&&\s*([a-zA-Z_][a-zA-Z0-9_]*)\)'
    replacement = rb'if(\1&&\2)'

    content, count = re.subn(pattern, replacement, content)

    if content != original_content:
        with open(filepath, 'wb') as f:
            f.write(content)
        print(f"Title bar patch applied: {count} replacement(s)")
        return True
    else:
        print("Warning: No title bar patterns found to patch")
        return False


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_MainWindowPage-*.js>")
        sys.exit(1)

    filepath = sys.argv[1]
    if not os.path.exists(filepath):
        print(f"Error: File not found: {filepath}")
        sys.exit(1)

    # Always exit 0 - patch is optional (some versions may not need it)
    patch_title_bar(filepath)
    sys.exit(0)
fix_title_bar_py_EOF
    else
        echo "Warning: Target not found for pattern: app.asar.contents/.vite/renderer/main_window/assets/MainWindowPage-*.js"
    fi




    # Repack app.asar
    asar pack app.asar.contents app.asar
    rm -rf app.asar.contents

    # Copy locales
    mkdir -p "$srcdir/app/locales"
    cp "$srcdir/extract/lib/net45/resources/"*.json "$srcdir/app/locales/" 2>/dev/null || true
}

package() {
    # Install application files
    install -dm755 "$pkgdir/usr/lib/$pkgname"
    cp -r "$srcdir/app"/* "$pkgdir/usr/lib/$pkgname/"

    # Install launcher script
    install -dm755 "$pkgdir/usr/bin"
    cat > "$pkgdir/usr/bin/claude-desktop" << 'EOF'
#!/bin/bash
exec electron /usr/lib/claude-desktop-bin/app.asar "$@"
EOF
    chmod +x "$pkgdir/usr/bin/claude-desktop"

    # Install desktop entry
    install -dm755 "$pkgdir/usr/share/applications"
    cat > "$pkgdir/usr/share/applications/claude-desktop.desktop" << 'EOF'
[Desktop Entry]
Name=Claude
Comment=Claude AI Desktop Application
Exec=claude-desktop %u
Icon=claude-desktop
Type=Application
Terminal=false
Categories=Office;Utility;Chat;
MimeType=x-scheme-handler/claude;
StartupWMClass=Claude
EOF

    # Extract and install icon
    if [ -f "$srcdir/extract/lib/net45/resources/TrayIconTemplate.png" ]; then
        install -Dm644 "$srcdir/extract/lib/net45/resources/TrayIconTemplate.png" \
            "$pkgdir/usr/share/icons/hicolor/256x256/apps/claude-desktop.png"
    fi
}

# vim: set ts=4 sw=4 et: