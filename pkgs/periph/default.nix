{
  lib,
  rustPlatform,
  pkg-config,
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

  # hidapi, under the keyboard libraries, links libudev.
  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ udev ];

  meta = {
    description = "Declarative settings for USB mice and keyboards";
    license = lib.licenses.gpl3Plus;
    mainProgram = "periph";
    platforms = lib.platforms.linux;
  };
}
