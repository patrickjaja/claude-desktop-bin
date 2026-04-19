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
# Computer Use — KDE Plasma Wayland
, spectacle ? null      # screenshot capture (KDE Plasma)
# Computer Use — GNOME Wayland
, gnome-screenshot ? null  # screenshot fallback (GNOME)
, glib ? null              # gsettings (flat mouse acceleration)
# Portal screenshots (GNOME 46+): needs python3 with gi module + gst-plugin-pipewire.
# On NixOS GNOME, these are typically available system-wide.
# To enable explicitly: python3.withPackages (ps: [ ps.pygobject3 ]) in systemPackages.
# Claude Code CLI — required for Cowork, Dispatch, and Code integration
, claude-code ? null    # auto-resolved by callPackage if in nixpkgs
# Other optional
, socat ? null          # faster Quick Entry toggle (~2ms vs ~25ms python3)
, nodejs ? null         # third-party MCP servers
# Extra PATH entries for binaries not packaged in Nix (e.g. npm global, nvm)
, extraSessionPaths ? []
}:

let
  # Updated automatically by CI (build-and-release.yml) on each release.
  version = "1.3109.0";
  hash = "sha256-ZP0GqFOgg+jZY8wAJObKPLx882wV4EBSdjU9jyKgy8A=";
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

  # Reverse-URL name ("name") becomes the .desktop filename; startupWMClass
  # must match Electron's reported app_id. Electron ignores Chromium's --class
  # flag *and* argv[0] (both silently dropped) — it reads /proc/self/exe and
  # takes the basename as the Wayland app_id / X11 WM_CLASS instance. So we
  # materialise a copy of Electron's libexec dir with the binary renamed.
  desktopItems = [
    (makeDesktopItem {
      name = "com.anthropic.claude-desktop";
      desktopName = "Claude";
      comment = "Claude AI Desktop Application";
      exec = "claude-desktop %u";
      icon = "claude-desktop";
      categories = [ "Office" "Utility" "Chat" ];
      mimeTypes = [ "x-scheme-handler/claude" ];
      startupWMClass = "com.anthropic.claude-desktop";
      terminal = false;
    })
  ];

  installPhase = ''
    runHook preInstall

    # Install app files
    mkdir -p $out/lib/claude-desktop/resources
    cp -r app/* $out/lib/claude-desktop/resources/

    # Materialise Electron's libexec dir inside our derivation with the binary
    # renamed to APP_ID. /proc/self/exe at runtime will resolve to this path
    # so the basename drives the Wayland app_id / X11 WM_CLASS.
    mkdir -p $out/libexec/claude-desktop
    cp -rL ${electron}/libexec/electron/. $out/libexec/claude-desktop/
    mv $out/libexec/claude-desktop/electron \
       $out/libexec/claude-desktop/com.anthropic.claude-desktop
    chmod +x $out/libexec/claude-desktop/com.anthropic.claude-desktop

    # Install launcher script (handles --toggle, --install-gnome-hotkey, --diagnose
    # and all Wayland/X11 detection, GPU fallback, etc.)
    mkdir -p $out/bin
    cp launcher/claude-desktop $out/lib/claude-desktop/launcher.sh
    chmod +x $out/lib/claude-desktop/launcher.sh
    makeWrapper $out/lib/claude-desktop/launcher.sh $out/bin/claude-desktop \
      --set CLAUDE_ELECTRON "$out/libexec/claude-desktop/com.anthropic.claude-desktop" \
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
