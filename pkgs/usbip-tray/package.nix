{
  lib,
  stdenv,
  wrapGAppsHook3,
  gobject-introspection,
  librsvg,
  python3,
  gtk3,
  libayatana-appindicator,
}:
stdenv.mkDerivation {
  pname = "usbip-tray";
  version = "1.0";
  src = ./.;
  nativeBuildInputs = [
    wrapGAppsHook3
    gobject-introspection
    librsvg
  ];
  buildInputs = [
    (python3.withPackages (ps: [ ps.pygobject3 ]))
    gtk3
    libayatana-appindicator
  ];
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    install -Dm755 app.py $out/bin/usbip-tray
    mkdir -p $out/share/usbip-tray/icons
    for icon in icons/*.svg; do
      rsvg-convert --width 64 --height 64 "$icon" \
        --output "$out/share/usbip-tray/icons/$(basename "$icon" .svg).png"
    done
    runHook postInstall
  '';
  meta = {
    description = "USB port sharing tray using USB/IP over SSH";
    platforms = lib.platforms.linux;
    mainProgram = "usbip-tray";
  };
}
