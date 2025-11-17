# Maintainer: patrickjaja <patrickjajaa@gmail.com>
# Contributor: Claude Desktop Linux Community
# AUR Package Repository: https://github.com/patrickjaja/claude-desktop-bin

pkgname=claude-desktop-bin
pkgver=1.0.734
pkgrel=1
pkgdesc="Claude AI Desktop Application (Official Binary - Linux Compatible)"
arch=('x86_64')
url="https://claude.ai"
license=('custom:Claude')
depends=('electron' 'nodejs')
makedepends=('p7zip' 'wget' 'asar' 'python')
provides=('claude-desktop')
conflicts=('claude-desktop')
source_x86_64=("Claude-Setup-x64-${pkgver}.exe::https://downloads.claude.ai/releases/win32/x64/1.0.734/Claude-b8f837f8b9db51221c5dce2de52fa05581927c64.exe")
sha256sums_x86_64=('f4e41b0b19f76851b533195936c25b1320bd4fb751e19dcad12b761b312d0c12')
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

    # Create Linux-compatible native module
    mkdir -p app.asar.contents/node_modules/claude-native
    cat > app.asar.contents/node_modules/claude-native/index.js << 'EOF'
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
EOF

    # Fix title bar detection issue
    local js_file=$(find app.asar.contents -name "MainWindowPage-*.js" 2>/dev/null | head -1)
    if [ -n "$js_file" ]; then
        sed -i -E 's/if\(!([a-zA-Z]+)[[:space:]]*&&[[:space:]]*([a-zA-Z]+)\)/if(\1 \&\& \2)/g' "$js_file"
    fi

    # Fix locale file loading using Python for more precise string replacement
    echo "Patching locale file paths..."

    python3 << 'EOF'
import os
import re

# Find the main index.js file
for root, dirs, files in os.walk("app.asar.contents"):
    for file in files:
        if file == "index.js" and ".vite/build" in root:
            filepath = os.path.join(root, file)
            print(f"Found index.js at: {filepath}")

            # Read the file
            with open(filepath, 'rb') as f:
                content = f.read()

            # Replace process.resourcesPath with our locale path
            # This handles the actual runtime value
            original_content = content
            content = content.replace(
                b'process.resourcesPath',
                b'"/usr/lib/claude-desktop-bin/locales"'
            )

            # Also try to replace any hardcoded electron paths
            content = re.sub(
                rb'/usr/lib/electron\d+/resources',
                b'/usr/lib/claude-desktop-bin/locales',
                content
            )

            # Write back if changed
            if content != original_content:
                with open(filepath, 'wb') as f:
                    f.write(content)
                print("Locale path patch applied successfully")
            else:
                print("Warning: No changes made to locale paths")

            break
EOF

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