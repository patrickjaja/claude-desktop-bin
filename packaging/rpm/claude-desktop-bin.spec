%define _build_id_links none
%global debug_package %{nil}

Name:           claude-desktop-bin
Version:        %{pkg_version}
Release:        %{?pkg_release}%{!?pkg_release:1}
Summary:        Claude AI Desktop Application for Linux

License:        Proprietary
URL:            https://claude.ai
Source0:        claude-desktop-%{pkg_version}-linux.tar.gz
Source1:        electron.zip

ExclusiveArch:  x86_64

Requires:       gtk3
Requires:       nss
Requires:       libXScrnSaver
Requires:       libXtst
Requires:       at-spi2-core
Requires:       libdrm
Requires:       mesa-libgbm
Requires:       alsa-lib
Requires:       libnotify

%description
Claude is an AI assistant created by Anthropic to be helpful,
harmless, and honest. This desktop application provides native
access to Claude with features including conversational AI,
code generation, document understanding, and system tray integration.

Note: This is an unofficial Linux port. Requires an Anthropic account.

%prep
# Extract tarball
mkdir -p tarball
tar -xzf %{SOURCE0} -C tarball

# Extract Electron
mkdir -p electron
unzip -q %{SOURCE1} -d electron

%install
rm -rf %{buildroot}

# Install Electron + app
mkdir -p %{buildroot}/usr/lib/claude-desktop
cp -a electron/* %{buildroot}/usr/lib/claude-desktop/
cp -a tarball/app/* %{buildroot}/usr/lib/claude-desktop/resources/

# Install launcher
mkdir -p %{buildroot}/usr/bin
cat > %{buildroot}/usr/bin/claude-desktop << 'LAUNCHER'
#!/bin/bash
export ELECTRON_OZONE_PLATFORM_HINT="${ELECTRON_OZONE_PLATFORM_HINT:-auto}"
exec /usr/lib/claude-desktop/electron /usr/lib/claude-desktop/resources/app.asar "$@"
LAUNCHER
chmod +x %{buildroot}/usr/bin/claude-desktop

# Install desktop file
mkdir -p %{buildroot}/usr/share/applications
cat > %{buildroot}/usr/share/applications/claude-desktop.desktop << 'DESKTOP'
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
DESKTOP

# Install icon
mkdir -p %{buildroot}/usr/share/icons/hicolor/256x256/apps
if [ -f tarball/icons/claude-desktop.png ]; then
    cp tarball/icons/claude-desktop.png \
        %{buildroot}/usr/share/icons/hicolor/256x256/apps/claude-desktop.png
fi

%post
# Ensure chrome-sandbox has SUID root (required by Chromium's setuid sandbox)
if [ -f /usr/lib/claude-desktop/chrome-sandbox ]; then
    chown root:root /usr/lib/claude-desktop/chrome-sandbox
    chmod 4755 /usr/lib/claude-desktop/chrome-sandbox
fi
if command -v update-desktop-database &>/dev/null; then
    update-desktop-database /usr/share/applications || true
fi
if command -v gtk-update-icon-cache &>/dev/null; then
    gtk-update-icon-cache /usr/share/icons/hicolor || true
fi

%postun
if command -v update-desktop-database &>/dev/null; then
    update-desktop-database /usr/share/applications || true
fi
if command -v gtk-update-icon-cache &>/dev/null; then
    gtk-update-icon-cache /usr/share/icons/hicolor || true
fi

%files
%attr(4755,root,root) /usr/lib/claude-desktop/chrome-sandbox
/usr/lib/claude-desktop/
/usr/bin/claude-desktop
/usr/share/applications/claude-desktop.desktop
/usr/share/icons/hicolor/256x256/apps/claude-desktop.png
