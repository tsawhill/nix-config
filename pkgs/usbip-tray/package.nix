{
  lib,
  stdenv,
  wrapGAppsHook3,
  gobject-introspection,
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
    runHook postInstall
  '';
  meta = {
    description = "USB port sharing tray using USB/IP over SSH";
    platforms = lib.platforms.linux;
    mainProgram = "usbip-tray";
  };
}
