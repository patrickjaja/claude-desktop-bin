# Maintainer: patrickjaja <patrickjajaa@gmail.com>
# Contributor: Claude Desktop Linux Community
# AUR Package Repository: https://github.com/patrickjaja/claude-desktop-bin

pkgname=claude-desktop-bin
pkgver=1.0.1307
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
source_x86_64=("Claude-Setup-x64-${pkgver}.exe::https://downloads.claude.ai/releases/win32/x64/1.0.1307/Claude-1ed8835ce5539ba2a894ab752752be672a17c0d8.exe")
sha256sums_x86_64=('4e6b99a9bd2d0f9e42048608b7f2a36fcf3224c97400564299c8a60b0b04196f')
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

// AuthRequest stub - not available on Linux, will cause fallback to system browser
class AuthRequest {
    static isAvailable() {
        return false;
    }

    async start(url, scheme, windowHandle) {
        throw new Error('AuthRequest not available on Linux');
    }

    cancel() {
        // no-op
    }
}

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
    KeyboardKey,
    AuthRequest
};
claude_native_js_EOF

    # Applying patch: fix_claude_code.py
    echo "Applying patch: fix_claude_code.py..."
    if ! python3 - "app.asar.contents/.vite/build/index.js" << 'fix_claude_code_py_EOF'
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

    print(f"=== Patch: fix_claude_code ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content
    failed = False

    # Patch 1: getBinaryPathIfReady() - Check /usr/bin/claude first on Linux
    old_binary_ready = b'async getBinaryPathIfReady(){return await this.binaryExists(this.requiredVersion)?this.getBinaryPath(this.requiredVersion):null}'
    new_binary_ready = b'async getBinaryPathIfReady(){console.log("[ClaudeCode] getBinaryPathIfReady called, platform:",process.platform);if(process.platform==="linux"){try{const fs=require("fs");const exists=fs.existsSync("/usr/bin/claude");console.log("[ClaudeCode] /usr/bin/claude exists:",exists);if(exists)return"/usr/bin/claude"}catch(e){console.log("[ClaudeCode] error checking /usr/bin/claude:",e)}}return await this.binaryExists(this.requiredVersion)?this.getBinaryPath(this.requiredVersion):null}'

    count1 = content.count(old_binary_ready)
    if count1 >= 1:
        content = content.replace(old_binary_ready, new_binary_ready)
        print(f"  [OK] getBinaryPathIfReady(): {count1} match(es)")
    else:
        print(f"  [FAIL] getBinaryPathIfReady(): 0 matches, expected >= 1")
        failed = True

    # Patch 2: getStatus() - Return Ready if system binary exists on Linux
    old_status = b'async getStatus(){if(await this.binaryExists(this.requiredVersion))'
    new_status = b'async getStatus(){console.log("[ClaudeCode] getStatus called, platform:",process.platform);if(process.platform==="linux"){try{const fs=require("fs");const exists=fs.existsSync("/usr/bin/claude");console.log("[ClaudeCode] /usr/bin/claude exists:",exists);if(exists){console.log("[ClaudeCode] returning Ready");return Rv.Ready}}catch(e){console.log("[ClaudeCode] error:",e)}}if(await this.binaryExists(this.requiredVersion))'

    count2 = content.count(old_status)
    if count2 >= 1:
        content = content.replace(old_status, new_status)
        print(f"  [OK] getStatus(): {count2} match(es)")
    else:
        print(f"  [FAIL] getStatus(): 0 matches, expected >= 1")
        failed = True

    # Check results
    if failed:
        print("  [FAIL] Some patterns did not match")
        return False

    # Write back if changed
    if content != original_content:
        with open(filepath, 'wb') as f:
            f.write(content)
        print("  [PASS] All patterns matched and applied")
        return True
    else:
        print("  [WARN] No changes made (patterns may have already been applied)")
        return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_claude_code(sys.argv[1])
    sys.exit(0 if success else 1)
fix_claude_code_py_EOF
    then
        echo "ERROR: Patch fix_claude_code.py FAILED - patterns did not match"
        echo "Please check if upstream changed the target file structure"
        exit 1
    fi

    # Applying patch: fix_locale_paths.py
    echo "Applying patch: fix_locale_paths.py..."
    if ! python3 - "app.asar.contents/.vite/build/index.js" << 'fix_locale_paths_py_EOF'
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

    print(f"=== Patch: fix_locale_paths ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content
    failed = False

    # Replace process.resourcesPath with our locale path
    old_resource_path = b'process.resourcesPath'
    new_resource_path = b'"/usr/lib/claude-desktop-bin/locales"'

    count1 = content.count(old_resource_path)
    if count1 >= 1:
        content = content.replace(old_resource_path, new_resource_path)
        print(f"  [OK] process.resourcesPath: {count1} match(es)")
    else:
        print(f"  [FAIL] process.resourcesPath: 0 matches, expected >= 1")
        failed = True

    # Also replace any hardcoded electron paths (optional - may not exist)
    pattern = rb'/usr/lib/electron\d+/resources'
    replacement = b'/usr/lib/claude-desktop-bin/locales'
    content, count2 = re.subn(pattern, replacement, content)
    if count2 > 0:
        print(f"  [OK] hardcoded electron paths: {count2} match(es)")
    else:
        print(f"  [INFO] hardcoded electron paths: 0 matches (optional)")

    # Check results
    if failed:
        print("  [FAIL] Required patterns did not match")
        return False

    # Write back if changed
    if content != original_content:
        with open(filepath, 'wb') as f:
            f.write(content)
        print("  [PASS] All required patterns matched and applied")
        return True
    else:
        print("  [WARN] No changes made (patterns may have already been applied)")
        return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_locale_paths(sys.argv[1])
    sys.exit(0 if success else 1)
fix_locale_paths_py_EOF
    then
        echo "ERROR: Patch fix_locale_paths.py FAILED - patterns did not match"
        echo "Please check if upstream changed the target file structure"
        exit 1
    fi

    # Applying patch: fix_native_frame.py
    echo "Applying patch: fix_native_frame.py..."
    if ! python3 - "app.asar.contents/.vite/build/index.js" << 'fix_native_frame_py_EOF'
#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Patch Claude Desktop to use native window frames on Linux.

On Linux/XFCE, frame:false doesn't work properly - the WM still adds decorations.
So we use frame:true for native window management, but also show Claude's internal
title bar for the hamburger menu and Claude icon.

IMPORTANT: Quick Entry window needs frame:false for transparency - we preserve that.

NOTE: As of version 1.0.1217+, the main window no longer explicitly sets frame:false,
so it defaults to native frames. This patch now only needs to verify the structure
is correct and preserve the Quick Entry window's frame:false setting.

Usage: python3 fix_native_frame.py <path_to_index.js>
"""

import sys
import os
import re


def patch_native_frame(filepath):
    """Patch BrowserWindow to use native frames on Linux (main window only)."""

    print(f"=== Patch: fix_native_frame ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content

    # Step 1: Check if transparent window pattern exists (Quick Entry)
    quick_entry_pattern = rb'transparent:!0,frame:!1'
    has_quick_entry = quick_entry_pattern in content
    if has_quick_entry:
        print(f"  [OK] Quick Entry pattern found (will preserve)")
    else:
        print(f"  [INFO] Quick Entry pattern not found (may be already patched)")

    # Step 2: Temporarily mark the Quick Entry pattern
    marker = b'__QUICK_ENTRY_FRAME_PRESERVE__'
    if has_quick_entry:
        content = content.replace(quick_entry_pattern, b'transparent:!0,' + marker)

    # Step 3: Replace frame:!1 (false) with frame:true for main window
    pattern = rb'frame\s*:\s*!1'
    replacement = b'frame:true'
    content, count = re.subn(pattern, replacement, content)
    if count > 0:
        print(f"  [OK] frame:!1 -> frame:true: {count} match(es)")
    else:
        # No frame:!1 found outside Quick Entry - this is OK for newer versions
        # The main window now uses titleBarStyle:"hidden" without explicit frame:false
        print(f"  [INFO] No frame:!1 found outside Quick Entry (main window uses native frames by default)")

    # Step 4: Restore Quick Entry frame setting
    if has_quick_entry:
        content = content.replace(b'transparent:!0,' + marker, quick_entry_pattern)
        print(f"  [OK] Restored Quick Entry frame:!1 (transparent)")

    # Write back if changed
    if content != original_content:
        with open(filepath, 'wb') as f:
            f.write(content)
        print("  [PASS] Native frame patched successfully")
        return True
    else:
        print("  [PASS] No changes needed (main window already uses native frames)")
        return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_native_frame(sys.argv[1])
    sys.exit(0 if success else 1)
fix_native_frame_py_EOF
    then
        echo "ERROR: Patch fix_native_frame.py FAILED - patterns did not match"
        echo "Please check if upstream changed the target file structure"
        exit 1
    fi

    # Applying patch: fix_quick_entry_position.py
    echo "Applying patch: fix_quick_entry_position.py..."
    if ! python3 - "app.asar.contents/.vite/build/index.js" << 'fix_quick_entry_position_py_EOF'
#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Patch Claude Desktop Quick Entry to spawn on the monitor where the cursor is.

The original code uses getPrimaryDisplay() for the fallback position, which
always spawns the Quick Entry window on the primary monitor (usually the
laptop screen). This patch changes it to use getDisplayNearestPoint() with
the cursor position, so the window appears on the monitor where the user
is currently working.

Usage: python3 fix_quick_entry_position.py <path_to_index.js>
"""

import sys
import os
import re


def patch_quick_entry_position(filepath):
    """Patch Quick Entry to spawn on cursor's monitor instead of primary display."""

    print(f"=== Patch: fix_quick_entry_position ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content
    failed = False

    # Patch 1: In position function - the fallback position generator
    # Pattern matches: function FUNCNAME(){const t=ELECTRON.screen.getPrimaryDisplay()
    # Function names change between versions (pTe, lPe, etc.), electron var changes (ce, de, etc.)
    pattern1 = rb'(function \w+\(\)\{const t=)(\w+)(\.screen\.)getPrimaryDisplay\(\)'

    def replacement1_func(m):
        electron_var = m.group(2).decode('utf-8')
        return (m.group(1) + m.group(2) + m.group(3) +
                f'getDisplayNearestPoint({electron_var}.screen.getCursorScreenPoint())'.encode('utf-8'))

    content, count1 = re.subn(pattern1, replacement1_func, content)
    if count1 > 0:
        print(f"  [OK] position function: {count1} match(es)")
    else:
        print(f"  [FAIL] position function: 0 matches, expected >= 1")
        failed = True

    # Patch 2: In fallback display lookup
    # Pattern matches: r||(r=ELECTRON.screen.getPrimaryDisplay())
    pattern2 = rb'r\|\|\(r=(\w+)\.screen\.getPrimaryDisplay\(\)\)'

    def replacement2_func(m):
        electron_var = m.group(1).decode('utf-8')
        return f'r||(r={electron_var}.screen.getDisplayNearestPoint({electron_var}.screen.getCursorScreenPoint()))'.encode('utf-8')

    content, count2 = re.subn(pattern2, replacement2_func, content)
    if count2 > 0:
        print(f"  [OK] fallback display: {count2} match(es)")
    else:
        print(f"  [FAIL] fallback display: 0 matches, expected >= 1")
        failed = True

    # Patch 3: Disabled - this optional enhancement caused syntax errors
    # The pattern only matched part of a function, leaving dangling code
    print(f"  [INFO] dTe() override: skipped (disabled)")

    # Check results
    if failed:
        print("  [FAIL] Required patterns did not match")
        return False

    # Write back if changed
    if content != original_content:
        with open(filepath, 'wb') as f:
            f.write(content)
        print("  [PASS] Quick Entry position patched successfully")
        return True
    else:
        print("  [WARN] No changes made (patterns may have already been applied)")
        return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_quick_entry_position(sys.argv[1])
    sys.exit(0 if success else 1)
fix_quick_entry_position_py_EOF
    then
        echo "ERROR: Patch fix_quick_entry_position.py FAILED - patterns did not match"
        echo "Please check if upstream changed the target file structure"
        exit 1
    fi

    # Applying patch: fix_title_bar.py
    echo "Applying patch: fix_title_bar.py..."
    local target_file=$(find app.asar.contents/.vite/renderer/main_window/assets -name "MainWindowPage-*.js" 2>/dev/null | head -1)
    if [ -n "$target_file" ]; then
        if ! python3 - "$target_file" << 'fix_title_bar_py_EOF'
#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/renderer/main_window/assets/MainWindowPage-*.js
# @patch-type: python
"""
Patch Claude Desktop to show internal title bar on Linux.

The original code has: if(!B&&e)return null
Where B = process.platform==="win32" (true on Windows)

Original behavior:
- Windows: !true=false, condition fails → title bar SHOWS
- Linux: !false=true, condition true → returns null → title bar HIDDEN

This patch changes: if(!B&&e) -> if(B&&e)
New behavior:
- Windows: true&&e=true → returns null → title bar hidden (uses native)
- Linux: false&&e=false → condition fails → title bar SHOWS

This gives Linux the same internal title bar that Windows has.

Usage: python3 fix_title_bar.py <path_to_MainWindowPage-*.js>
"""

import sys
import os
import re


def patch_title_bar(filepath):
    """Patch the title bar detection to show on Linux."""

    print(f"=== Patch: fix_title_bar ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content

    # Fix: if(!B&&e) -> if(B&&e) - removes the negation
    pattern = rb'if\(!([a-zA-Z_][a-zA-Z0-9_]*)\s*&&\s*([a-zA-Z_][a-zA-Z0-9_]*)\)'
    replacement = rb'if(\1&&\2)'

    content, count = re.subn(pattern, replacement, content)

    if count >= 1:
        print(f"  [OK] title bar condition: {count} match(es)")
    else:
        print(f"  [FAIL] title bar condition: 0 matches, expected >= 1")
        return False

    # Write back if changed
    if content != original_content:
        with open(filepath, 'wb') as f:
            f.write(content)
        print("  [PASS] Title bar patched successfully")
        return True
    else:
        print("  [WARN] No changes made (patterns may have already been applied)")
        return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_MainWindowPage-*.js>")
        sys.exit(1)

    success = patch_title_bar(sys.argv[1])
    sys.exit(0 if success else 1)
fix_title_bar_py_EOF
        then
            echo "ERROR: Patch fix_title_bar.py FAILED - patterns did not match"
            echo "Please check if upstream changed the target file structure"
            exit 1
        fi
    else
        echo "ERROR: Target not found for pattern: app.asar.contents/.vite/renderer/main_window/assets/MainWindowPage-*.js"
        exit 1
    fi

    # Applying patch: fix_tray_dbus.py
    echo "Applying patch: fix_tray_dbus.py..."
    if ! python3 - "app.asar.contents/.vite/build/index.js" << 'fix_tray_dbus_py_EOF'
#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Patch Claude Desktop tray menu handler to prevent DBus race conditions.

The tray icon setup can be called multiple times concurrently, causing DBus
"already exported" errors. This patch:
1. Makes the tray function async
2. Adds a mutex guard to prevent concurrent calls
3. Adds a delay after Tray.destroy() to allow DBus cleanup

Based on: https://github.com/aaddrick/claude-desktop-debian/blob/main/build.sh

Usage: python3 fix_tray_dbus.py <path_to_index.js>
"""

import sys
import os
import re


def patch_tray_dbus(filepath):
    """Patch the tray menu handler to prevent DBus race conditions."""

    print(f"=== Patch: fix_tray_dbus ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content
    failed = False

    # Step 1: Find the tray function name from menuBarEnabled listener
    match = re.search(rb'on\("menuBarEnabled",\(\)=>\{(\w+)\(\)\}\)', content)
    if not match:
        print("  [FAIL] menuBarEnabled listener: 0 matches, expected >= 1")
        failed = True
        tray_func = None
    else:
        tray_func = match.group(1)
        print(f"  [OK] menuBarEnabled listener: found tray function '{tray_func.decode()}'")

    # Step 2: Find tray variable name
    tray_var = None
    if tray_func:
        pattern = rb'\}\);let (\w+)=null;(?:async )?function ' + tray_func
        match = re.search(pattern, content)
        if not match:
            print("  [FAIL] tray variable: 0 matches, expected >= 1")
            failed = True
        else:
            tray_var = match.group(1)
            print(f"  [OK] tray variable: found '{tray_var.decode()}'")

    # Step 3: Make the function async (if not already)
    if tray_func:
        old_func = b'function ' + tray_func + b'(){'
        new_func = b'async function ' + tray_func + b'(){'
        if old_func in content and b'async function ' + tray_func not in content:
            content = content.replace(old_func, new_func)
            print(f"  [OK] async conversion: made {tray_func.decode()}() async")
        elif b'async function ' + tray_func in content:
            print(f"  [INFO] async conversion: already async")
        else:
            print(f"  [FAIL] async conversion: function pattern not found")
            failed = True

    # Step 4: Find first const variable in the function
    first_const = None
    if tray_func:
        pattern = rb'async function ' + tray_func + rb'\(\)\{(?:if\(' + tray_func + rb'\._running\)[^}]*?)?const (\w+)='
        match = re.search(pattern, content)
        if not match:
            print("  [FAIL] first const in function: 0 matches")
            failed = True
        else:
            first_const = match.group(1)
            print(f"  [OK] first const in function: found '{first_const.decode()}'")

    # Step 5: Add mutex guard (if not already present)
    if tray_func and first_const:
        mutex_check = tray_func + b'._running'
        if mutex_check not in content:
            old_start = b'async function ' + tray_func + b'(){const ' + first_const + b'='
            mutex_code = (
                b'async function ' + tray_func + b'(){if(' + tray_func + b'._running)return;' +
                tray_func + b'._running=true;setTimeout(()=>' + tray_func + b'._running=false,500);const ' +
                first_const + b'='
            )
            if old_start in content:
                content = content.replace(old_start, mutex_code)
                print(f"  [OK] mutex guard: added")
            else:
                print(f"  [FAIL] mutex guard: insertion point not found")
                failed = True
        else:
            print(f"  [INFO] mutex guard: already present")

    # Step 6: Add delay after Tray.destroy() for DBus cleanup
    if tray_var:
        old_destroy = tray_var + b'&&(' + tray_var + b'.destroy(),' + tray_var + b'=null)'
        new_destroy = tray_var + b'&&(' + tray_var + b'.destroy(),' + tray_var + b'=null,await new Promise(r=>setTimeout(r,50)))'

        if old_destroy in content and b'await new Promise' not in content:
            content = content.replace(old_destroy, new_destroy)
            print(f"  [OK] DBus cleanup delay: added after {tray_var.decode()}.destroy()")
        elif b'await new Promise' in content:
            print(f"  [INFO] DBus cleanup delay: already present")
        else:
            print(f"  [FAIL] DBus cleanup delay: destroy pattern not found")
            failed = True

    # Check results
    if failed:
        print("  [FAIL] Some required patterns did not match")
        return False

    # Write back if changed
    if content != original_content:
        with open(filepath, 'wb') as f:
            f.write(content)
        print("  [PASS] All required patterns matched and applied")
        return True
    else:
        print("  [WARN] No changes made (patterns may have already been applied)")
        return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_tray_dbus(sys.argv[1])
    sys.exit(0 if success else 1)
fix_tray_dbus_py_EOF
    then
        echo "ERROR: Patch fix_tray_dbus.py FAILED - patterns did not match"
        echo "Please check if upstream changed the target file structure"
        exit 1
    fi

    # Applying patch: fix_tray_path.py
    echo "Applying patch: fix_tray_path.py..."
    if ! python3 - "app.asar.contents/.vite/build/index.js" << 'fix_tray_path_py_EOF'
#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Patch Claude Desktop to fix tray icon path on Linux.

On Linux, process.resourcesPath points to the Electron resources directory
(e.g., /usr/lib/electron/resources/) but our tray icons are installed to
/usr/lib/claude-desktop-bin/locales/. This patch redirects the tray icon
path lookup to use our package's directory.

The wTe() function is used to get the resources path for tray icons.
We patch it to return our locales directory on Linux.

Usage: python3 fix_tray_path.py <path_to_index.js>
"""

import sys
import os
import re


def patch_tray_path(filepath):
    """Patch the tray icon resources path to use our package directory."""

    print(f"=== Patch: fix_tray_path ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content
    patches_applied = 0

    # Pattern 1: Generic function pattern with variable electron/process module names
    # Pattern: function FUNCNAME(){return ELECTRON.app.isPackaged?PROCESS.resourcesPath:...}
    # Variable names change between versions (ce->de, pn->gn, etc.)
    pattern1 = rb'(function \w+\(\)\{return )(\w+)(\.app\.isPackaged\?)(\w+)(\.resourcesPath)(:[^}]+\})'

    def replacement1_func(m):
        prefix = m.group(1)
        electron_var = m.group(2)
        middle = m.group(3)
        process_var = m.group(4)
        suffix = m.group(5) + m.group(6)
        # Insert Linux check: (process.platform==="linux"?"/usr/lib/claude-desktop-bin/locales":process.resourcesPath)
        return (prefix + electron_var + middle +
                b'(' + process_var + b'.platform==="linux"?"/usr/lib/claude-desktop-bin/locales":' +
                process_var + b'.resourcesPath)' + m.group(6))

    content, count1 = re.subn(pattern1, replacement1_func, content)
    if count1 > 0:
        patches_applied += count1
        print(f"  [OK] generic resources path function: {count1} match(es)")

    # Pattern 2: Alternative pattern with process.resourcesPath directly (no variable)
    if patches_applied == 0:
        pattern2 = rb'(function \w+\(\)\{return )(\w+)(\.app\.isPackaged\?)process\.resourcesPath(:[^}]+\})'

        def replacement2_func(m):
            prefix = m.group(1)
            electron_var = m.group(2)
            middle = m.group(3)
            suffix = m.group(4)
            return (prefix + electron_var + middle +
                    b'(process.platform==="linux"?"/usr/lib/claude-desktop-bin/locales":process.resourcesPath)' + suffix)

        content, count2 = re.subn(pattern2, replacement2_func, content)
        if count2 > 0:
            patches_applied += count2
            print(f"  [OK] process.resourcesPath function: {count2} match(es)")

    # Check results - at least one pattern must match
    if patches_applied == 0:
        print(f"  [FAIL] No patterns matched (tried 2 alternatives), expected >= 1")
        return False

    # Write back if changed
    if content != original_content:
        with open(filepath, 'wb') as f:
            f.write(content)
        print("  [PASS] Tray path patched successfully")
        return True
    else:
        print("  [WARN] No changes made (patterns may have already been applied)")
        return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_tray_path(sys.argv[1])
    sys.exit(0 if success else 1)
fix_tray_path_py_EOF
    then
        echo "ERROR: Patch fix_tray_path.py FAILED - patterns did not match"
        echo "Please check if upstream changed the target file structure"
        exit 1
    fi




    # Repack app.asar
    asar pack app.asar.contents app.asar
    rm -rf app.asar.contents

    # Copy locales
    mkdir -p "$srcdir/app/locales"
    cp "$srcdir/extract/lib/net45/resources/"*.json "$srcdir/app/locales/" 2>/dev/null || true

    # Copy tray icons (must be in filesystem, not inside asar, for Electron Tray API)
    echo "Copying tray icon files..."
    cp "$srcdir/extract/lib/net45/resources/TrayIconTemplate"*.png "$srcdir/app/locales/" 2>/dev/null || true
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