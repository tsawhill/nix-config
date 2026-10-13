{
  lib,
  rustPlatform,
  pkg-config,
  makeWrapper,
  udev,
  libGL,
  libxkbcommon,
  wayland,
  wl-clipboard,
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
    makeWrapper
  ];
  buildInputs = [ udev ];

  # egui loads GL and Wayland at runtime; wl-copy backs "Copy as Nix".
  postFixup = ''
    patchelf --add-rpath ${
      lib.makeLibraryPath [
        libGL
        libxkbcommon
        wayland
      ]
    } $out/bin/periph-gui
    wrapProgram $out/bin/periph-gui --prefix PATH : ${lib.makeBinPath [ wl-clipboard ]}
  '';

  meta = {
    description = "Declarative settings for USB mice and keyboards";
    license = lib.licenses.gpl3Plus;
    mainProgram = "periph";
    platforms = lib.platforms.linux;
  };
}
