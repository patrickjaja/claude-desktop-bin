# Maintainer: Your Name <your@email.com>
pkgname=claude-desktop-bin
pkgver=0.7.5
pkgrel=1
pkgdesc="Unofficial Linux build of Claude Desktop AI assistant"
arch=('x86_64')
url="https://github.com/k3d3/claude-desktop-linux-flake"
license=('custom')
depends=(
    'electron'
    'nodejs'
)
makedepends=(
    'p7zip'
    'imagemagick'
    'icoutils'
    'rust'
    'cargo'
)
source=(
    "Claude-Setup-x64.exe::https://storage.googleapis.com/osprey-downloads-c02f6a0d-347c-492b-a752-3e0651722e97/nest-win-x64/Claude-Setup-x64.exe"
    "git+https://github.com/k3d3/claude-desktop-linux-flake.git"
)
sha256sums=('SKIP' 'SKIP')  # We'll add proper hashes later

prepare() {
    cd "${srcdir}"
    # Build patchy-cnb
    cd claude-desktop-linux-flake/patchy-cnb
    cargo build --release
}

package() {
    cd "${srcdir}"
    
    # Create working directory
    mkdir -p build
    cd build

    # Extract the Windows installer
    7z x ../Claude-Setup-x64.exe
    7z x "AnthropicClaude-${pkgver}-full.nupkg"

    # Extract and convert icons
    wrestool -x -t 14 lib/net45/claude.exe -o claude.ico
    icotool -x claude.ico
    
    # Install icons
    for f in claude_*.png; do
    if [ -f "$f" ]; then
        size=$(identify -format "%wx%h" "$f" | cut -d'x' -f1)
        install -Dm644 "$f" "${pkgdir}/usr/share/icons/hicolor/${size}x${size}/apps/claude-desktop.png"
    fi
	done
    # Process app.asar
    mkdir -p electron-app
    cp "lib/net45/resources/app.asar" electron-app/
    cp -r "lib/net45/resources/app.asar.unpacked" electron-app/
    cd electron-app
    asar extract app.asar app.asar.contents

    # Replace native bindings with our Linux version
    local _target_triple="x86_64-unknown-linux-gnu"
    install -Dm755 "${srcdir}/claude-desktop-linux-flake/patchy-cnb/target/release/libpatchy_cnb.so" \
        "app.asar.contents/node_modules/claude-native/claude-native-binding.node"
    cp "app.asar.contents/node_modules/claude-native/claude-native-binding.node" \
        "app.asar.unpacked/node_modules/claude-native/claude-native-binding.node"

    # Copy Tray icons
    mkdir -p app.asar.contents/resources
    cp ../lib/net45/resources/Tray* app.asar.contents/resources/

    # Repack app.asar
    asar pack app.asar.contents app.asar

    # Install application files
    install -dm755 "${pkgdir}/usr/lib/claude-desktop"
    cp app.asar "${pkgdir}/usr/lib/claude-desktop/"
    cp -r app.asar.unpacked "${pkgdir}/usr/lib/claude-desktop/"

    # Create desktop entry
    install -Dm644 /dev/stdin "${pkgdir}/usr/share/applications/claude-desktop.desktop" << EOF
[Desktop Entry]
Name=Claude
Exec=claude-desktop %u
Icon=claude-desktop
Type=Application
Categories=Office;Utility;
Comment=Claude Desktop AI assistant
EOF

    # Create launcher script
    install -Dm755 /dev/stdin "${pkgdir}/usr/bin/claude-desktop" << EOF
#!/bin/sh
exec electron /usr/lib/claude-desktop/app.asar "\$@"
EOF
}
