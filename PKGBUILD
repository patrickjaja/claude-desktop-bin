# Maintainer: patrickjaja <patrickjajaa@gmail.com>
# Contributor: Claude Desktop Linux Community
# AUR Package Repository: https://github.com/patrickjaja/claude-desktop-bin

pkgname=claude-desktop-bin
pkgver=1.0.3218
pkgrel=1
pkgdesc="Claude AI Desktop Application (Official Binary - Linux Compatible)"
arch=('x86_64')
url="https://claude.ai"
license=('custom:Claude')
depends=('electron' 'nodejs')
makedepends=('p7zip' 'wget' 'asar' 'python' 'icoutils')
optdepends=('claude-code: Claude Code CLI for agentic coding features (npm i -g @anthropic-ai/claude-code)')
provides=('claude-desktop')
conflicts=('claude-desktop')
source_x86_64=("Claude-Setup-x64-${pkgver}.exe::https://downloads.claude.ai/releases/win32/x64/1.0.3218/Claude-8679c9141fe246eb88af18130504c064d14b9004.exe")
sha256sums_x86_64=('ade7b25c1db6d6e9963df4ce2f0456de364a6a12b67d7bc7647ffb3f69c3dcb3')
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

    # Applying patch: enable_local_agent_mode.py
    echo "Applying patch: enable_local_agent_mode.py..."
    if ! python3 - "app.asar.contents/.vite/build/index.js" << 'enable_local_agent_mode_py_EOF'
#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Enable Local Agent Mode (chillingSlothFeat) on Linux.

The original code gates this feature with `process.platform!=="darwin"` check,
returning {status:"unavailable"} on Linux. This patch removes that check to
enable the Local Agent Mode feature (Claude Code for Desktop with git worktrees).

This feature provides:
- Local agent sessions with isolated git worktrees
- Claude Code integration in Desktop app
- MCP server support for agent sessions
- PTY terminal support

NOTE: This does NOT enable:
- yukonSilver/SecureVM (requires @ant/claude-swift macOS native module)
- Echo/Screen capture (requires @ant/claude-swift macOS native module)
- Native Quick Entry (requires macOS-specific Swift code)

Usage: python3 enable_local_agent_mode.py <path_to_index.js>
"""

import sys
import os
import re


def patch_local_agent_mode(filepath):
    """Enable Local Agent Mode (chillingSlothFeat) on Linux by patching qWe function."""

    print(f"=== Patch: enable_local_agent_mode ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content
    failed = False

    # Patch 1: Modify qWe() function (chillingSlothFeat)
    # Original: function qWe(){return process.platform!=="darwin"?{status:"unavailable"}:{status:"supported"}}
    # Changed:  function qWe(){return{status:"supported"}}
    #
    # Pattern matches the darwin-only check and replaces with always-supported
    pattern1 = rb'function qWe\(\)\{return process\.platform!=="darwin"\?\{status:"unavailable"\}:\{status:"supported"\}\}'
    replacement1 = b'function qWe(){return{status:"supported"}}'

    content, count1 = re.subn(pattern1, replacement1, content)
    if count1 > 0:
        print(f"  [OK] qWe (chillingSlothFeat): {count1} match(es)")
    else:
        # Try alternative pattern in case of slight variations
        pattern1_alt = rb'(function qWe\(\)\{return )process\.platform!=="darwin"\?\{status:"unavailable"\}:(\{status:"supported"\})\}'
        content, count1 = re.subn(pattern1_alt, rb'\1\2}', content)
        if count1 > 0:
            print(f"  [OK] qWe (chillingSlothFeat) alt: {count1} match(es)")
        else:
            print(f"  [FAIL] qWe (chillingSlothFeat): 0 matches, expected 1")
            failed = True

    # Patch 2: Modify zWe() function (quietPenguin)
    # This feature is also darwin-only but may be related to agent mode
    # Original: function zWe(){return process.platform!=="darwin"?{status:"unavailable"}:{status:"supported"}}
    # Changed:  function zWe(){return{status:"supported"}}
    pattern2 = rb'function zWe\(\)\{return process\.platform!=="darwin"\?\{status:"unavailable"\}:\{status:"supported"\}\}'
    replacement2 = b'function zWe(){return{status:"supported"}}'

    content, count2 = re.subn(pattern2, replacement2, content)
    if count2 > 0:
        print(f"  [OK] zWe (quietPenguin): {count2} match(es)")
    else:
        print(f"  [INFO] zWe (quietPenguin): 0 matches (may not exist in this version)")

    # Check results
    if failed:
        print("  [FAIL] Required patterns did not match")
        return False

    # Write back if changed
    if content != original_content:
        with open(filepath, 'wb') as f:
            f.write(content)
        print("  [PASS] Local Agent Mode enabled successfully")
        return True
    else:
        print("  [WARN] No changes made (patterns may have already been applied)")
        return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_local_agent_mode(sys.argv[1])
    sys.exit(0 if success else 1)
enable_local_agent_mode_py_EOF
    then
        echo "ERROR: Patch enable_local_agent_mode.py FAILED - patterns did not match"
        echo "Please check if upstream changed the target file structure"
        exit 1
    fi

    # Applying patch: fix_app_quit.py
    echo "Applying patch: fix_app_quit.py..."
    if ! python3 - "app.asar.contents/.vite/build/index.js" << 'fix_app_quit_py_EOF'
#!/usr/bin/env python3
"""
@patch-target: app.asar.contents/.vite/build/index.js
@patch-type: python

Fix app not quitting after cleanup completes.

After the will-quit handler calls preventDefault() and runs cleanup,
calling app.quit() again becomes a no-op on Linux. The will-quit event
never fires again, leaving the app stuck.

Solution: Use app.exit(0) instead of app.quit() after cleanup is complete.
Since all cleanup handlers have already run (mcp-shutdown, quick-entry-cleanup,
prototype-cleanup), we can safely force exit. Using setImmediate ensures
the exit happens in the next event loop tick.
"""

import sys
import re

def main():
    if len(sys.argv) != 2:
        print("Usage: fix_app_quit.py <file>")
        sys.exit(1)

    file_path = sys.argv[1]

    with open(file_path, 'rb') as f:
        content = f.read()

    print("=== Patch: fix_app_quit ===")
    print(f"  Target: {file_path}")

    # Original pattern: clearTimeout(n)}XX&&YY.app.quit()}
    # Variables change between versions (e.g., S_&&he → TS&&ce)
    # The XX&&YY.app.quit() doesn't work after preventDefault() on Linux
    # Replace with setImmediate + app.exit(0) for reliable exit
    pattern = rb'(clearTimeout\(\w+\)\})(\w+)&&(\w+)(\.app\.quit\(\))'

    def replacement(m):
        flag_var = m.group(2).decode('utf-8')
        electron_var = m.group(3).decode('utf-8')
        return f'{m.group(1).decode("utf-8")}if({flag_var}){{setImmediate(()=>{electron_var}.app.exit(0))}}'.encode('utf-8')

    new_content, count = re.subn(pattern, replacement, content)

    if count == 0:
        print("  [WARN] app.quit pattern: 0 matches (may need pattern update)")
        # Debug: check for any app.quit patterns
        if b'.app.quit()' in content:
            print("  [INFO] Found '.app.quit()' in file but pattern didn't match")
        sys.exit(0)

    print(f"  [OK] app.quit -> app.exit: {count} match(es)")

    with open(file_path, 'wb') as f:
        f.write(new_content)

    print("  [PASS] App quit patched successfully")
    sys.exit(0)

if __name__ == "__main__":
    main()
fix_app_quit_py_EOF
    then
        echo "ERROR: Patch fix_app_quit.py FAILED - patterns did not match"
        echo "Please check if upstream changed the target file structure"
        exit 1
    fi

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

    # Patch 1: getHostPlatform() - Add Linux support
    # This is the root cause - it throws "Unsupported platform" for Linux
    old_platform = b'getHostPlatform(){const e=process.arch;if(process.platform==="darwin")return e==="arm64"?"darwin-arm64":"darwin-x64";if(process.platform==="win32")return"win32-x64";throw new Error(`Unsupported platform: ${process.platform}-${e}`)}'
    new_platform = b'getHostPlatform(){const e=process.arch;if(process.platform==="darwin")return e==="arm64"?"darwin-arm64":"darwin-x64";if(process.platform==="win32")return"win32-x64";if(process.platform==="linux")return e==="arm64"?"linux-arm64":"linux-x64";throw new Error(`Unsupported platform: ${process.platform}-${e}`)}'

    count1 = content.count(old_platform)
    if count1 >= 1:
        content = content.replace(old_platform, new_platform)
        print(f"  [OK] getHostPlatform(): {count1} match(es)")
    else:
        print(f"  [FAIL] getHostPlatform(): 0 matches, expected >= 1")
        failed = True

    # Patch 2: getBinaryPathIfReady() - Check /usr/bin/claude first on Linux
    # IMPORTANT: Check Linux BEFORE calling getHostTarget() for safety
    old_binary_ready = b'async getBinaryPathIfReady(){const e=this.getHostTarget();return await this.binaryExistsForTarget(e,this.requiredVersion)?this.getBinaryPathForTarget(e,this.requiredVersion):null}'
    new_binary_ready = b'async getBinaryPathIfReady(){if(process.platform==="linux"){try{const fs=require("fs");if(fs.existsSync("/usr/bin/claude"))return"/usr/bin/claude"}catch(err){}}const e=this.getHostTarget();return await this.binaryExistsForTarget(e,this.requiredVersion)?this.getBinaryPathForTarget(e,this.requiredVersion):null}'

    count2 = content.count(old_binary_ready)
    if count2 >= 1:
        content = content.replace(old_binary_ready, new_binary_ready)
        print(f"  [OK] getBinaryPathIfReady(): {count2} match(es)")
    else:
        print(f"  [FAIL] getBinaryPathIfReady(): 0 matches, expected >= 1")
        failed = True

    # Patch 3: getStatus() - Return Ready if system binary exists on Linux
    # IMPORTANT: Check Linux BEFORE calling getHostTarget() for safety
    old_status = b'async getStatus(){const e=this.getHostTarget();if(this.preparingPromise)return Yo.Updating;if(await this.binaryExistsForTarget(e,this.requiredVersion))'
    new_status = b'async getStatus(){if(process.platform==="linux"){try{const fs=require("fs");if(fs.existsSync("/usr/bin/claude")){return Yo.Ready}return Yo.NotInstalled}catch(err){return Yo.NotInstalled}}const e=this.getHostTarget();if(this.preparingPromise)return Yo.Updating;if(await this.binaryExistsForTarget(e,this.requiredVersion))'

    count3 = content.count(old_status)
    if count3 >= 1:
        content = content.replace(old_status, new_status)
        print(f"  [OK] getStatus(): {count3} match(es)")
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

    # Applying patch: fix_node_host.py
    echo "Applying patch: fix_node_host.py..."
    if ! python3 - "app.asar.contents/.vite/build/index.js" << 'fix_node_host_py_EOF'
#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Patch Claude Desktop to fix MCP node host path on Linux.

The fix_locale_paths.py patch replaces process.resourcesPath with our locale path,
but this breaks the MCP node host path construction. This patch fixes it by
using app.getAppPath() which correctly points to the app.asar location.

Usage: python3 fix_node_host.py <path_to_index.js>
"""

import sys
import os
import re


def patch_node_host(filepath):
    """Patch the MCP node host path to use app.getAppPath()."""

    print(f"=== Patch: fix_node_host ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content

    # Pattern matches the nodeHostPath assignment after fix_locale_paths.py has run
    # It captures:
    #   Group 1: electron module variable (de, ce, etc.)
    #   Group 2: path module variable ($e, etc.) - note [\w$]+ to match $
    pattern = rb'this\.nodeHostPath=([\w$]+)\.app\.isPackaged\?([\w$]+)\.join\("/usr/lib/claude-desktop-bin/locales","app\.asar","\.vite","build","mcp-runtime","nodeHost\.js"\):\2\.join\(\1\.app\.getAppPath\(\),"\.vite","build","mcp-runtime","nodeHost\.js"\)'

    def replacement(m):
        electron_var = m.group(1)
        path_var = m.group(2)
        # Use getAppPath() unconditionally - it returns the correct path on Linux
        return b'this.nodeHostPath=' + path_var + b'.join(' + electron_var + b'.app.getAppPath(),".vite","build","mcp-runtime","nodeHost.js")'

    content, count = re.subn(pattern, replacement, content)

    if count > 0:
        print(f"  [OK] nodeHostPath: {count} match(es)")
    else:
        print(f"  [FAIL] nodeHostPath: 0 matches, expected 1")
        print(f"  This patch must run AFTER fix_locale_paths.py")
        return False

    # Write back if changed
    if content != original_content:
        with open(filepath, 'wb') as f:
            f.write(content)
        print("  [PASS] Node host path patched successfully")
        return True
    else:
        print("  [WARN] No changes made")
        return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_node_host(sys.argv[1])
    sys.exit(0 if success else 1)
fix_node_host_py_EOF
    then
        echo "ERROR: Patch fix_node_host.py FAILED - patterns did not match"
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
    # Pattern matches: VAR||(VAR=ELECTRON.screen.getPrimaryDisplay())
    # Variable name changes between versions (r, n, etc.), so use backreference
    pattern2 = rb'(\w)\|\|\(\1=(\w+)\.screen\.getPrimaryDisplay\(\)\)'

    def replacement2_func(m):
        var_name = m.group(1).decode('utf-8')
        electron_var = m.group(2).decode('utf-8')
        return f'{var_name}||({var_name}={electron_var}.screen.getDisplayNearestPoint({electron_var}.screen.getCursorScreenPoint()))'.encode('utf-8')

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

    # Applying patch: fix_startup_settings.py
    echo "Applying patch: fix_startup_settings.py..."
    if ! python3 - "app.asar.contents/.vite/build/index.js" << 'fix_startup_settings_py_EOF'
#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Patch Claude Desktop to fix startup settings on Linux.

On Linux, Electron's app.getLoginItemSettings() returns undefined values for
openAtLogin and executableWillLaunchAtLogin, causing validation errors.
This patch adds a Linux platform check to return false immediately.

Linux autostart is typically handled via .desktop files in ~/.config/autostart/
which is outside the app's control anyway.

Usage: python3 fix_startup_settings.py <path_to_index.js>
"""

import sys
import os
import re


def patch_startup_settings(filepath):
    """Patch startup settings to handle Linux correctly."""

    print(f"=== Patch: fix_startup_settings ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content
    patches_applied = 0

    # Pattern 1: isStartupOnLoginEnabled function
    # Add Linux platform check before the existing env var check
    pattern1 = rb'isStartupOnLoginEnabled\(\)\{if\(process\.env\.CLAUDE_AVOID_READING_LOGING_ITEM_SETTINGS\)return!1;'
    replacement1 = b'isStartupOnLoginEnabled(){if(process.platform==="linux"||process.env.CLAUDE_AVOID_READING_LOGING_ITEM_SETTINGS)return!1;'

    content, count1 = re.subn(pattern1, replacement1, content)
    if count1 > 0:
        patches_applied += count1
        print(f"  [OK] isStartupOnLoginEnabled: {count1} match(es)")
    else:
        print(f"  [FAIL] isStartupOnLoginEnabled: 0 matches")

    # Pattern 2: setStartupOnLoginEnabled function - make it a no-op on Linux
    # Find the function and add early return for Linux
    pattern2 = rb'setStartupOnLoginEnabled\((\w+)\)\{re\.debug\('

    def replacement2_func(m):
        arg_var = m.group(1)
        return b'setStartupOnLoginEnabled(' + arg_var + b'){if(process.platform==="linux")return;re.debug('

    content, count2 = re.subn(pattern2, replacement2_func, content)
    if count2 > 0:
        patches_applied += count2
        print(f"  [OK] setStartupOnLoginEnabled: {count2} match(es)")
    else:
        print(f"  [INFO] setStartupOnLoginEnabled: 0 matches (optional)")

    # Check results
    if patches_applied == 0:
        print(f"  [FAIL] No patterns matched")
        return False

    # Write back if changed
    if content != original_content:
        with open(filepath, 'wb') as f:
            f.write(content)
        print("  [PASS] Startup settings patched successfully")
        return True
    else:
        print("  [WARN] No changes made")
        return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_startup_settings(sys.argv[1])
    sys.exit(0 if success else 1)
fix_startup_settings_py_EOF
    then
        echo "ERROR: Patch fix_startup_settings.py FAILED - patterns did not match"
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
        # Use full pattern with () to avoid matching similar function names like _Be
        async_check = b'async function ' + tray_func + b'(){'
        if old_func in content and async_check not in content:
            content = content.replace(old_func, new_func)
            print(f"  [OK] async conversion: made {tray_func.decode()}() async")
        elif async_check in content:
            print(f"  [INFO] async conversion: already async")
        else:
            print(f"  [FAIL] async conversion: function pattern not found")
            failed = True

    # Step 4: Find first const variable in the function
    # Pattern accounts for: async function _B(){if(!ce.app.isReady())return;const t=
    # or with mutex: async function _B(){if(_B._running)return;_B._running=true;...const t=
    first_const = None
    if tray_func:
        # More flexible pattern that allows various preamble code before the first const
        # Match function start, then non-greedy to first 'const'
        pattern = rb'async function ' + tray_func + rb'\(\)\{.+?const (\w+)='
        match = re.search(pattern, content)
        if not match:
            print("  [FAIL] first const in function: 0 matches")
            failed = True
        else:
            first_const = match.group(1)
            print(f"  [OK] first const in function: found '{first_const.decode()}'")

    # Step 5: Add mutex guard (if not already present)
    # Insert mutex right after function opening brace
    if tray_func and first_const:
        mutex_check = tray_func + b'._running'
        if mutex_check not in content:
            # Match function declaration and insert mutex at the start
            old_start = b'async function ' + tray_func + b'(){'
            mutex_prefix = (
                b'async function ' + tray_func + b'(){if(' + tray_func + b'._running)return;' +
                tray_func + b'._running=true;setTimeout(()=>' + tray_func + b'._running=false,500);'
            )
            if old_start in content:
                content = content.replace(old_start, mutex_prefix)
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

        if old_destroy in content and new_destroy not in content:
            content = content.replace(old_destroy, new_destroy)
            print(f"  [OK] DBus cleanup delay: added after {tray_var.decode()}.destroy()")
        elif new_destroy in content:
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

    # Applying patch: fix_tray_icon_theme.py
    echo "Applying patch: fix_tray_icon_theme.py..."
    if ! python3 - "app.asar.contents/.vite/build/index.js" << 'fix_tray_icon_theme_py_EOF'
#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Patch Claude Desktop to use correct tray icon based on theme on Linux.

On Windows, the app checks nativeTheme.shouldUseDarkColors to select the
appropriate icon (light icon for dark theme, dark icon for light theme).
On Linux, it always uses TrayIconTemplate.png regardless of theme.

This patch adds theme detection for Linux to use:
- TrayIconTemplate.png for light panels (dark icon)
- TrayIconTemplate-Dark.png for dark panels (light icon)

Usage: python3 fix_tray_icon_theme.py <path_to_index.js>
"""

import sys
import os
import re


def patch_tray_icon_theme(filepath):
    """Patch tray icon selection to respect theme on Linux."""

    print(f"=== Patch: fix_tray_icon_theme ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content

    # Pattern: The tray icon selection logic
    # Original: Si?e=de.nativeTheme.shouldUseDarkColors?"Tray-Win32-Dark.ico":"Tray-Win32.ico":e="TrayIconTemplate.png"
    # We want to change the Linux branch to also check the theme
    #
    # The variable names:
    # - Si = isWindows check
    # - de = electron module
    # - e = icon filename variable

    # Match the pattern with flexible variable names
    pattern = rb'([\w$]+)\?(\w+)=(\w+)\.nativeTheme\.shouldUseDarkColors\?"Tray-Win32-Dark\.ico":"Tray-Win32\.ico":\2="TrayIconTemplate\.png"'

    def replacement(m):
        is_win_var = m.group(1)  # Si
        icon_var = m.group(2)     # e
        electron_var = m.group(3) # de
        # On Windows: use .ico files with theme check
        # On Linux: use .png files with theme check
        return (is_win_var + b'?' + icon_var + b'=' + electron_var +
                b'.nativeTheme.shouldUseDarkColors?"Tray-Win32-Dark.ico":"Tray-Win32.ico":' +
                icon_var + b'=' + electron_var +
                b'.nativeTheme.shouldUseDarkColors?"TrayIconTemplate-Dark.png":"TrayIconTemplate.png"')

    content, count = re.subn(pattern, replacement, content)

    if count > 0:
        print(f"  [OK] tray icon theme logic: {count} match(es)")
    else:
        print(f"  [FAIL] tray icon theme logic: 0 matches")
        return False

    # Write back if changed
    if content != original_content:
        with open(filepath, 'wb') as f:
            f.write(content)
        print("  [PASS] Tray icon theme patched successfully")
        return True
    else:
        print("  [WARN] No changes made")
        return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_tray_icon_theme(sys.argv[1])
    sys.exit(0 if success else 1)
fix_tray_icon_theme_py_EOF
    then
        echo "ERROR: Patch fix_tray_icon_theme.py FAILED - patterns did not match"
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

    # Applying patch: fix_utility_process_kill.py
    echo "Applying patch: fix_utility_process_kill.py..."
    if ! python3 - "app.asar.contents/.vite/build/index.js" << 'fix_utility_process_kill_py_EOF'
#!/usr/bin/env python3
"""
@patch-target: app.asar.contents/.vite/build/index.js
@patch-type: python

Fix UtilityProcess not terminating on app exit.

When using the integrated Node.js server for MCP, the fallback kill
after SIGTERM timeout sends another SIGTERM instead of SIGKILL,
causing the process to remain alive and preventing app exit.

Original pattern found in code:
  const a=(s=this.process)==null?void 0:s.kill();te.info(`Killing utiltiy proccess again

Note: "utiltiy" and "proccess" are typos in the original Anthropic code.
"""

import sys
import re

def main():
    if len(sys.argv) != 2:
        print("Usage: fix_utility_process_kill.py <file>")
        sys.exit(1)

    file_path = sys.argv[1]

    with open(file_path, 'rb') as f:
        content = f.read()

    print("=== Patch: fix_utility_process_kill ===")
    print(f"  Target: {file_path}")

    # Pattern: The setTimeout callback that tries to kill the UtilityProcess
    # after 5 seconds. Matches:
    #   const a=(s=this.process)==null?void 0:s.kill();te.info(`Killing utiltiy proccess again
    # Uses \w+ to capture minified variable names (s, a) flexibly
    pattern = rb'(const \w+=\(\w+=this\.process\)==null\?void 0:\w+)(\.kill\(\))(;\w+\.info\(`Killing utiltiy proccess again)'

    def replacement(m):
        # Replace .kill() with .kill("SIGKILL")
        return m.group(1) + b'.kill("SIGKILL")' + m.group(3)

    new_content, count = re.subn(pattern, replacement, content)

    if count == 0:
        print("  [WARN] UtilityProcess kill pattern: 0 matches (may need pattern update)")
        # Debug: show what we're looking for
        if b'Killing utiltiy proccess again' in content:
            print("  [INFO] Found 'Killing utiltiy proccess again' string in file")
            # Try to find nearby context
            ctx = re.search(rb'.{50}Killing utiltiy proccess again.{20}', content)
            if ctx:
                print(f"  [DEBUG] Context: {ctx.group(0)}")
        print("  [PASS] No changes needed (pattern may have changed)")
        sys.exit(0)  # Don't fail build, just warn

    print(f"  [OK] UtilityProcess SIGKILL fix: {count} match(es)")

    with open(file_path, 'wb') as f:
        f.write(new_content)

    print("  [PASS] UtilityProcess kill patched successfully")
    sys.exit(0)

if __name__ == "__main__":
    main()
fix_utility_process_kill_py_EOF
    then
        echo "ERROR: Patch fix_utility_process_kill.py FAILED - patterns did not match"
        echo "Please check if upstream changed the target file structure"
        exit 1
    fi

    # Applying patch: fix_vm_session_handlers.py
    echo "Applying patch: fix_vm_session_handlers.py..."
    if ! python3 - "app.asar.contents/.vite/build/index.js" << 'fix_vm_session_handlers_py_EOF'
#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Patch Claude Desktop to handle ClaudeVM and LocalAgentModeSessions IPC on Linux.

The claude.ai web frontend and popup windows may generate runtime UUIDs for IPC channels
that differ from the hardcoded UUID in the main process handlers. This causes "No handler
registered" errors on Linux.

This patch:
1. Modifies ClaudeVM implementation to return Linux-appropriate values immediately
2. Ensures graceful degradation when VM features are not available
3. Suppresses VM-related functionality on Linux since it's not supported

Usage: python3 fix_vm_session_handlers.py <path_to_index.js>
"""

import sys
import os
import re


def patch_vm_session_handlers(filepath):
    """Add Linux-specific handling for ClaudeVM and LocalAgentModeSessions."""

    print(f"=== Patch: fix_vm_session_handlers ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content
    patches_applied = 0

    # Patch 1: Modify the ClaudeVM getDownloadStatus to always return NotDownloaded on Linux
    # This prevents the UI from trying to download the VM
    old_vm_status = b'getDownloadStatus(){return WBe()?Zc.Downloading:IS()?Zc.Ready:Zc.NotDownloaded}'
    new_vm_status = b'getDownloadStatus(){if(process.platform==="linux"){return Zc.NotDownloaded}return WBe()?Zc.Downloading:IS()?Zc.Ready:Zc.NotDownloaded}'

    count1 = content.count(old_vm_status)
    if count1 >= 1:
        content = content.replace(old_vm_status, new_vm_status)
        print(f"  [OK] ClaudeVM.getDownloadStatus: {count1} match(es)")
        patches_applied += 1
    else:
        print(f"  [WARN] ClaudeVM.getDownloadStatus pattern not found")

    # Patch 2: Modify the ClaudeVM getRunningStatus to always return Offline on Linux
    old_vm_running = b'async getRunningStatus(){return await ty()?qd.Ready:qd.Offline}'
    new_vm_running = b'async getRunningStatus(){if(process.platform==="linux"){return qd.Offline}return await ty()?qd.Ready:qd.Offline}'

    count2 = content.count(old_vm_running)
    if count2 >= 1:
        content = content.replace(old_vm_running, new_vm_running)
        print(f"  [OK] ClaudeVM.getRunningStatus: {count2} match(es)")
        patches_applied += 1
    else:
        print(f"  [WARN] ClaudeVM.getRunningStatus pattern not found")

    # Patch 3: Modify the download function to fail gracefully on Linux
    old_vm_download = b'async download(){try{return await Qhe(),{success:IS()}}'
    new_vm_download = b'async download(){if(process.platform==="linux"){return{success:false,error:"VM download not supported on Linux. Install claude-code from npm: npm install -g @anthropic-ai/claude-code"}}try{return await Qhe(),{success:IS()}}'

    count3 = content.count(old_vm_download)
    if count3 >= 1:
        content = content.replace(old_vm_download, new_vm_download)
        print(f"  [OK] ClaudeVM.download: {count3} match(es)")
        patches_applied += 1
    else:
        print(f"  [WARN] ClaudeVM.download pattern not found")

    # Patch 4: Modify startVM to fail gracefully on Linux
    old_vm_start = b'async startVM(e){try{return await Jhe(e),{success:!0}}'
    new_vm_start = b'async startVM(e){if(process.platform==="linux"){return{success:false,error:"VM not supported on Linux"}}try{return await Jhe(e),{success:!0}}'

    count4 = content.count(old_vm_start)
    if count4 >= 1:
        content = content.replace(old_vm_start, new_vm_start)
        print(f"  [OK] ClaudeVM.startVM: {count4} match(es)")
        patches_applied += 1
    else:
        print(f"  [WARN] ClaudeVM.startVM pattern not found")

    # Patch 5: Add global IPC error handler to suppress known Linux unsupported feature errors
    # Find the app initialization and add error handler
    # Look for ce.app.on pattern and add error suppression
    old_app_ready = b"ce.app.on(\"ready\",async()=>{"
    new_app_ready = b"ce.app.on(\"ready\",async()=>{if(process.platform===\"linux\"){process.on(\"uncaughtException\",(e)=>{if(e.message&&(e.message.includes(\"ClaudeVM\")||e.message.includes(\"LocalAgentModeSessions\"))){console.log(\"[LinuxPatch] Suppressing unsupported feature error:\",e.message);return}throw e})};"

    count5 = content.count(old_app_ready)
    if count5 >= 1:
        content = content.replace(old_app_ready, new_app_ready)
        print(f"  [OK] App error handler: {count5} match(es)")
        patches_applied += 1
    else:
        # Try alternative pattern
        old_app_ready_alt = b'ce.app.on("ready",()=>{'
        new_app_ready_alt = b'ce.app.on("ready",()=>{if(process.platform==="linux"){process.on("uncaughtException",(e)=>{if(e.message&&(e.message.includes("ClaudeVM")||e.message.includes("LocalAgentModeSessions"))){console.log("[LinuxPatch] Suppressing unsupported feature error:",e.message);return}throw e})};'

        count5_alt = content.count(old_app_ready_alt)
        if count5_alt >= 1:
            content = content.replace(old_app_ready_alt, new_app_ready_alt)
            print(f"  [OK] App error handler (alt): {count5_alt} match(es)")
            patches_applied += 1
        else:
            print(f"  [WARN] App ready pattern not found")

    # Check results
    if patches_applied == 0:
        print("  [FAIL] No patches could be applied")
        return False

    if content == original_content:
        print("  [WARN] No changes made (patterns may have already been applied)")
        return True

    # Verify syntax (basic check)
    try:
        # Check for balanced braces (very basic validation)
        open_braces = content.count(b'{')
        close_braces = content.count(b'}')
        if open_braces != close_braces:
            print(f"  [WARN] Brace mismatch: {open_braces} open, {close_braces} close")
    except:
        pass

    # Write back
    with open(filepath, 'wb') as f:
        f.write(content)
    print(f"  [PASS] {patches_applied} patches applied")
    return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_vm_session_handlers(sys.argv[1])
    sys.exit(0 if success else 1)
fix_vm_session_handlers_py_EOF
    then
        echo "ERROR: Patch fix_vm_session_handlers.py FAILED - patterns did not match"
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

    # Extract and install icon from setupIcon.ico (full-color Claude logo)
    icotool -x -o "$srcdir/" "$srcdir/extract/setupIcon.ico"
    # Use the largest icon (256x256) - index 6 in the ico file
    install -Dm644 "$srcdir/setupIcon_6_256x256x32.png" \
        "$pkgdir/usr/share/icons/hicolor/256x256/apps/claude-desktop.png"
}

# vim: set ts=4 sw=4 et:
