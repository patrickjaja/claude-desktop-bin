{ lib
, stdenvNoCC
, fetchurl
, electron
, makeWrapper
, makeDesktopItem
, copyDesktopItems
}:

let
  # Update these values when a new version is released.
  # Run packaging/nix/update-hash.sh to compute the new hash.
  version = "1.1.3918";
  hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
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
