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
  pname = "airvpn-tray";
  version = "1.0";

  src = ./.;

  nativeBuildInputs = [
    wrapGAppsHook3
    gobject-introspection
  ];

  # python3 stays in buildInputs so patchShebangs resolves the applet's
  # `#!/usr/bin/env python3` to this environment, pygobject included.
  buildInputs = [
    (python3.withPackages (ps: with ps; [ pygobject3 ]))
    gtk3
    libayatana-appindicator
  ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 airvpn-tray.py $out/bin/airvpn-tray
    runHook postInstall
  '';

  meta = {
    description = "Tray applet for switching between AirVPN NetworkManager profiles";
    platforms = lib.platforms.linux;
    mainProgram = "airvpn-tray";
  };
}
