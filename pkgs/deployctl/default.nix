{
  lib,
  rustPlatform,
}:

rustPlatform.buildRustPackage {
  pname = "deployctl";
  version = "0.1.0";

  src = lib.cleanSource ./.;
  cargoLock.lockFile = ./Cargo.lock;

  meta = {
    description = "Typed deployment controller for the nix-config Colmena fleet";
    license = lib.licenses.mit;
    mainProgram = "deployctl";
    platforms = lib.platforms.linux;
  };
}
