{
  lib,
  rustPlatform,
}:

rustPlatform.buildRustPackage {
  pname = "periph";
  version = "0.1.0";

  src = lib.cleanSource ./.;
  cargoLock.lockFile = ./Cargo.lock;

  meta = {
    description = "Declarative settings for USB mice and keyboards";
    license = lib.licenses.gpl3Plus;
    mainProgram = "periph";
    platforms = lib.platforms.linux;
  };
}
