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

ExclusiveArch:  x86_64 aarch64

Requires:       gtk3
Requires:       nss
Requires:       libXScrnSaver
Requires:       libXtst
Requires:       at-spi2-core
Requires:       libdrm
Requires:       mesa-libgbm
Requires:       alsa-lib
Requires:       libnotify
# Computer Use — X11/XWayland
Suggests:       xdotool
Suggests:       scrot
Suggests:       ImageMagick
Suggests:       wmctrl
# Computer Use — all Wayland compositors (input automation)
Suggests:       ydotool
# Computer Use — Wayland/wlroots (Sway, Hyprland)
Suggests:       grim
Suggests:       jq
# Computer Use — KDE Plasma Wayland
Suggests:       spectacle
# Computer Use — GNOME Wayland
Suggests:       glib2
Suggests:       python3-gobject
Suggests:       gstreamer1-plugin-pipewire
Suggests:       gnome-screenshot
# Computer Use — Hyprland-specific
Suggests:       hyprland
# Cowork socket health check
Suggests:       socat
# MCP servers requiring system Node.js
Suggests:       nodejs

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

# Install launcher (full launcher from tarball with Wayland/X11 detection,
# GPU fallback, SingletonLock cleanup, cowork socket cleanup, and logging)
mkdir -p %{buildroot}/usr/bin
install -m755 tarball/launcher/claude-desktop %{buildroot}/usr/bin/claude-desktop

# Install desktop file.
# Filename must match APP_ID in the launcher (com.anthropic.claude-desktop)
# so xdg-desktop-portal can resolve our systemd-scope / cgroup identity.
mkdir -p %{buildroot}/usr/share/applications
cat > %{buildroot}/usr/share/applications/com.anthropic.claude-desktop.desktop << 'DESKTOP'
[Desktop Entry]
Name=Claude
Comment=Claude AI Desktop Application
Exec=claude-desktop %u
Icon=claude-desktop
Type=Application
Terminal=false
Categories=Office;Utility;Chat;
MimeType=x-scheme-handler/claude;
StartupWMClass=com.anthropic.claude-desktop
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
# Ensure repo config has metadata_expire for timely updates
REPO_FILE="/etc/yum.repos.d/claude-desktop.repo"
if [ -f "$REPO_FILE" ] && ! grep -q '^metadata_expire=' "$REPO_FILE"; then
    echo 'metadata_expire=300' >> "$REPO_FILE"
fi

%postun
if command -v update-desktop-database &>/dev/null; then
    update-desktop-database /usr/share/applications || true
fi
if command -v gtk-update-icon-cache &>/dev/null; then
    gtk-update-icon-cache /usr/share/icons/hicolor || true
fi

%files
/usr/lib/claude-desktop/
/usr/bin/claude-desktop
/usr/share/applications/com.anthropic.claude-desktop.desktop
/usr/share/icons/hicolor/256x256/apps/claude-desktop.png
