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
, xclip ? null          # clipboard access
, wmctrl ? null         # running app detection
, xrandr ? null         # display enumeration
# Computer Use — Wayland session (Sway, Hyprland, etc.)
, ydotool ? null        # input automation
, grim ? null           # screenshot capture (wlroots)
, slurp ? null          # region selection
, wl-clipboard ? null   # clipboard access
, wlr-randr ? null      # display enumeration (wlroots)
, hyprland ? null       # cursor positioning (Hyprland only)
# Other optional
, socat ? null          # cowork socket health check
, nodejs ? null         # third-party MCP servers
}:

let
  # Updated automatically by CI (update-aur.yml) on each release.
  version = "1.1.9134";
  hash = "sha256-QzUSy/7qE/xymCr9bG2uSiVDLzXfyJFoeVesBqNZ/DA=";
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

  desktopItems = [
    (makeDesktopItem {
      name = "claude-desktop";
      desktopName = "Claude";
      comment = "Claude AI Desktop Application";
      exec = "claude-desktop %u";
      icon = "claude-desktop";
      categories = [ "Office" "Utility" "Chat" ];
      mimeTypes = [ "x-scheme-handler/claude" ];
      startupWMClass = "Claude";
      terminal = false;
    })
  ];

  installPhase = ''
    runHook preInstall

    # Install app files
    mkdir -p $out/lib/claude-desktop/resources
    cp -r app/* $out/lib/claude-desktop/resources/

    # Install launcher
    mkdir -p $out/bin
    makeWrapper ${electron}/bin/electron $out/bin/claude-desktop \
      --set ELECTRON_OZONE_PLATFORM_HINT "auto" \
      --set ELECTRON_FORCE_IS_PACKAGED "true" \
      --set ELECTRON_USE_SYSTEM_TITLE_BAR "1" \
      --add-flags "--disable-features=CustomTitlebar" \
      ${lib.optionalString (xdotool != null) "--prefix PATH : ${xdotool}/bin"} \
      ${lib.optionalString (scrot != null) "--prefix PATH : ${scrot}/bin"} \
      ${lib.optionalString (xclip != null) "--prefix PATH : ${xclip}/bin"} \
      ${lib.optionalString (wmctrl != null) "--prefix PATH : ${wmctrl}/bin"} \
      ${lib.optionalString (xrandr != null) "--prefix PATH : ${xrandr}/bin"} \
      ${lib.optionalString (socat != null) "--prefix PATH : ${socat}/bin"} \
      ${lib.optionalString (hyprland != null) "--prefix PATH : ${hyprland}/bin"} \
      ${lib.optionalString (ydotool != null) "--prefix PATH : ${ydotool}/bin"} \
      ${lib.optionalString (grim != null) "--prefix PATH : ${grim}/bin"} \
      ${lib.optionalString (slurp != null) "--prefix PATH : ${slurp}/bin"} \
      ${lib.optionalString (wl-clipboard != null) "--prefix PATH : ${wl-clipboard}/bin"} \
      ${lib.optionalString (wlr-randr != null) "--prefix PATH : ${wlr-randr}/bin"} \
      ${lib.optionalString (nodejs != null) "--prefix PATH : ${nodejs}/bin"} \
      --add-flags "$out/lib/claude-desktop/resources/app.asar"

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
    platforms = [ "x86_64-linux" ];
    maintainers = [ ];
    mainProgram = "claude-desktop";
  };
}
