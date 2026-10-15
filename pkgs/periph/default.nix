{
  lib,
  rustPlatform,
  pkg-config,
  wrapGAppsHook4,
  gtk4,
  udev,
}:

rustPlatform.buildRustPackage {
  pname = "periph";
  version = "0.1.0";

  src = lib.cleanSource ./.;
  cargoLock = {
    lockFile = ./Cargo.lock;
    # monsgeek-keyboard/-transport come from git, pinned by rev in Cargo.lock.
    allowBuiltinFetchGit = true;
  };
  buildFeatures = [ "gui" ];

  # hidapi, under the keyboard libraries, links libudev.
  nativeBuildInputs = [
    pkg-config
    wrapGAppsHook4
  ];
  buildInputs = [
    gtk4
    udev
  ];

  meta = {
    description = "Declarative settings for USB mice and keyboards";
    license = lib.licenses.gpl3Plus;
    mainProgram = "periph";
    platforms = lib.platforms.linux;
  };
}
