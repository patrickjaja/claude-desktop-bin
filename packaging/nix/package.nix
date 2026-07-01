{ lib
, stdenvNoCC
, fetchurl
, electron
, makeWrapper
, makeDesktopItem
, copyDesktopItems
# Computer Use — X11/XWayland session
, xdotool ? null       # input automation + Quick Entry positioning
, scrot ? null          # screenshot capture
, imagemagick ? null    # screenshot fallback (import) and crop (convert)
, wmctrl ? null         # running app detection
# Computer Use — Wayland session (Sway, Hyprland — wlroots compositors)
, ydotool ? null        # input automation (requires ydotoold daemon)
, grim ? null           # screenshot capture (wlroots)
, jq ? null             # window queries on Sway (used with swaymsg)
, hyprland ? null       # cursor positioning (Hyprland only)
# Computer Use — KDE Plasma Wayland (bundled bridge has glibc mismatch on NixOS)
, spectacle ? null      # screenshot fallback (KDE Plasma on NixOS)
# Computer Use — GNOME Wayland
, gnome-screenshot ? null  # screenshot fallback (GNOME)
, glib ? null              # gsettings (flat mouse acceleration)
# Portal screenshots (GNOME 46+): needs python3 with gi module + gst-plugin-pipewire.
# On NixOS GNOME, these are typically available system-wide.
# To enable explicitly: python3.withPackages (ps: [ ps.pygobject3 ]) in systemPackages.
# Claude Code CLI — required for Cowork, Dispatch, and Code integration
, claude-code ? null    # auto-resolved by callPackage if in nixpkgs
# Cowork agent workspace VM (also requires /dev/kvm + kvm group membership).
# NOTE: putting qemu on PATH is necessary but NOT sufficient on NixOS: the app's
# capability probe searches for OVMF UEFI firmware at fixed /usr/share/... paths
# (see fix_cowork_firmware_paths_linux), which NixOS does not populate. Full NixOS
# Cowork support additionally needs the firmware exposed at one of those paths
# (e.g. via an activation-script symlink into /usr/share/edk2/x64/) — tracked as a
# known limitation. virtiofsd is bundled in the app payload.
, qemu ? null           # provides qemu-system-x86_64 for the Cowork VM
, socat ? null          # faster Quick Entry toggle (~2ms vs ~25ms python3)
, nodejs ? null         # third-party MCP servers
# Extra PATH entries for binaries not packaged in Nix (e.g. npm global, nvm)
, extraSessionPaths ? []
}:

let
  # Updated automatically by CI (build-and-release.yml) on each release.
  version = "1.17377.2";
  hash = "sha256-zDp+vB7Yd2xH7OtJX65qx21VR2e/YOmvb6WVT8tzJng="; # TODO: CI updates this hash after building the release tarball
  # The release tarball now also ships the official Electron runtime under
  # electron/ (extracted from Anthropic's Linux .deb). On NixOS, however, that
  # glibc-linked binary won't run without autoPatchelf + a runtime closure, so we
  # keep using the nixpkgs `electron` derivation (idiomatic, sandbox-correct) and
  # consume ONLY the patched app/ payload from the tarball. Pin `electron` to the
  # major version the app expects (Electron 42; see the tarball's electron/version)
  # via an override at call site if your nixpkgs default diverges.
in
stdenvNoCC.mkDerivation {
  pname = "claude-desktop-bin";
  inherit version;

  src = fetchurl {
    url = "https://github.com/patrickjaja/claude-desktop-bin/releases/download/v${version}/claude-desktop-${version}-linux.tar.gz";
    inherit hash;
  };

  sourceRoot = ".";

  nativeBuildInputs = [ makeWrapper copyDesktopItems ];

  # "name" becomes the .desktop filename. It is "claude-desktop" so the installed
  # file is claude-desktop.desktop, matching the app's *live* app_id - Chromium's
  # GetXdgAppId() reads the app's desktopName ("claude-desktop.desktop" in
  # app.asar package.json), strips ".desktop", and ignores the binary basename
  # / --class / argv[0]. On native Wayland there is no WM_CLASS, so KWin/GNOME
  # match the window to its .desktop by app_id; if the basename doesn't equal the
  # app_id the dock icon is generic and Alt+Tab shows a duplicate (issue #148).
  # startupWMClass=claude-desktop fixes the X11/XWayland path. The binary rename
  # below is kept only as a cosmetic argv[0] / scope hint; it does NOT set
  # WM_CLASS. Content mirrors the official Claude Desktop .deb.
  desktopItems = [
    (makeDesktopItem {
      name = "claude-desktop";
      desktopName = "Claude";
      genericName = "AI Assistant";
      comment = "Desktop application for Claude.ai";
      keywords = [ "AI" "Chat" "Assistant" "Claude" "Code" "LLM" ];
      exec = "claude-desktop %U";
      icon = "claude-desktop";
      categories = [ "Utility" "Development" ];
      mimeTypes = [ "x-scheme-handler/claude" ];
      startupNotify = true;
      startupWMClass = "claude-desktop";
      terminal = false;
      # second-instance just focuses mainWindow; suppress GNOME's "New Window" item
      singleMainWindow = true;
      actions = {
        NewChat = {
          name = "New chat";
          exec = "claude-desktop claude://claude.ai/new";
        };
        NewCode = {
          name = "New Claude Code session";
          exec = "claude-desktop claude://code/new";
        };
      };
    })
  ];

  installPhase = ''
    runHook preInstall

    # Install app files
    mkdir -p $out/lib/claude-desktop/resources
    cp -r app/* $out/lib/claude-desktop/resources/

    # Materialise Electron's libexec dir inside our derivation with the binary
    # renamed to "claude" (cosmetic argv[0] / systemd-scope hint only). The
    # Wayland app_id / X11 WM_CLASS is NOT derived from this basename - it comes
    # from the app's desktopName ("claude-desktop"); see startupWMClass above.
    mkdir -p $out/libexec/claude-desktop
    cp -rL ${electron}/libexec/electron/. $out/libexec/claude-desktop/
    mv $out/libexec/claude-desktop/electron \
       $out/libexec/claude-desktop/claude
    chmod +x $out/libexec/claude-desktop/claude

    # Install launcher script (handles --toggle, --install-gnome-hotkey, --diagnose
    # and all Wayland/X11 detection, GPU fallback, etc.)
    mkdir -p $out/bin
    cp launcher/claude-desktop $out/lib/claude-desktop/launcher.sh
    chmod +x $out/lib/claude-desktop/launcher.sh
    makeWrapper $out/lib/claude-desktop/launcher.sh $out/bin/claude-desktop \
      --set CLAUDE_ELECTRON "$out/libexec/claude-desktop/claude" \
      --set CLAUDE_APP_ASAR "$out/lib/claude-desktop/resources/app.asar" \
      --set ELECTRON_OZONE_PLATFORM_HINT "auto" \
      --set ELECTRON_FORCE_IS_PACKAGED "true" \
      --set ELECTRON_USE_SYSTEM_TITLE_BAR "1" \
      ${lib.optionalString (xdotool != null) "--prefix PATH : ${xdotool}/bin"} \
      ${lib.optionalString (scrot != null) "--prefix PATH : ${scrot}/bin"} \
      ${lib.optionalString (imagemagick != null) "--prefix PATH : ${imagemagick}/bin"} \
      ${lib.optionalString (wmctrl != null) "--prefix PATH : ${wmctrl}/bin"} \
      ${lib.optionalString (socat != null) "--prefix PATH : ${socat}/bin"} \
      ${lib.optionalString (hyprland != null) "--prefix PATH : ${hyprland}/bin"} \
      ${lib.optionalString (ydotool != null) "--prefix PATH : ${ydotool}/bin"} \
      ${lib.optionalString (grim != null) "--prefix PATH : ${grim}/bin"} \
      ${lib.optionalString (jq != null) "--prefix PATH : ${jq}/bin"} \
      ${lib.optionalString (spectacle != null) "--prefix PATH : ${spectacle}/bin"} \
      ${lib.optionalString (gnome-screenshot != null) "--prefix PATH : ${gnome-screenshot}/bin"} \
      ${lib.optionalString (glib != null) "--prefix PATH : ${glib}/bin"} \
      ${lib.optionalString (nodejs != null) "--prefix PATH : ${nodejs}/bin"} \
      ${lib.optionalString (qemu != null) "--prefix PATH : ${qemu}/bin"} \
      ${lib.optionalString (claude-code != null && extraSessionPaths == []) "--prefix PATH : ${claude-code}/bin"} \
      ${lib.concatMapStringsSep " \\\n      " (p:
        let path = if builtins.isString p then p else "${p}/bin";
        in "--prefix PATH : ${path}"
      ) extraSessionPaths}

    # Install icon
    if [ -f icons/claude-desktop.png ]; then
      mkdir -p $out/share/icons/hicolor/256x256/apps
      cp icons/claude-desktop.png $out/share/icons/hicolor/256x256/apps/claude-desktop.png
    fi

    # Upstream license notice (tarball root, from the official .deb's
    # usr/share/doc). Guarded: pre-2026-07 release tarballs lack it, and the
    # flake may still pin one of those.
    if [ -f copyright ]; then
      install -Dm644 copyright $out/share/licenses/claude-desktop/copyright
    fi

    runHook postInstall
  '';

  meta = with lib; {
    description = "Claude AI Desktop Application for Linux";
    homepage = "https://claude.ai";
    license = licenses.unfree;
    platforms = [ "x86_64-linux" "aarch64-linux" ];
    maintainers = [ ];
    mainProgram = "claude-desktop";
  };
}
