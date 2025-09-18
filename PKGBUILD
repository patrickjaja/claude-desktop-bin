# Maintainer: patrickjaja <patrickjajaa@gmail.com>
# Contributor: Claude Desktop Linux Community

pkgname=claude-desktop-bin
pkgver=0.13.19
pkgrel=1
pkgdesc="Claude AI Desktop Application (Official Binary - Linux Compatible)"
arch=('x86_64')
url="https://claude.ai"
license=('custom:Claude')
depends=('electron' 'nodejs')
makedepends=('p7zip' 'wget' 'asar' 'python')
provides=('claude-desktop')
conflicts=('claude-desktop')
source_x86_64=("Claude-Setup-x64-${pkgver}.exe::https://storage.googleapis.com/osprey-downloads-c02f6a0d-347c-492b-a752-3e0651722e97/nest-win-x64/Claude-Setup-x64.exe")
sha256sums_x86_64=('0f00a04d20692b6f2c4420540416ad3ec681650fb2c8bac96c0ae24a47f57fc1')
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