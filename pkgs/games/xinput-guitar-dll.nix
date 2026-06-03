{
  lib,
  stdenvNoCC,
  pkgsCross,
}:

stdenvNoCC.mkDerivation {
  pname = "xinput-guitar-dll";
  version = "0-unstable-2026-06-02";

  src = ./.;

  nativeBuildInputs = [
    pkgsCross.mingw32.stdenv.cc
  ];

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild

    i686-w64-mingw32-gcc \
      -O2 \
      -Wall \
      -Wextra \
      -shared \
      -o xinput1_3.dll \
      xinput-guitar-dll.c \
      xinput-guitar-dll.def \
      -ldinput8 \
      -ldxguid \
      -luser32

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    install -Dm0644 xinput1_3.dll "$out/share/games/xinput-guitar-dll/xinput1_3.dll"
    install -Dm0644 xinput-guitar-dll.c "$out/share/games/xinput-guitar-dll/source/xinput-guitar-dll.c"
    install -Dm0644 xinput-guitar-dll.def "$out/share/games/xinput-guitar-dll/source/xinput-guitar-dll.def"
    install -Dm0755 /dev/stdin "$out/bin/xinput-guitar-dll-path" <<EOF
    #!/bin/sh
    printf '%s\n' "$out/share/games/xinput-guitar-dll/xinput1_3.dll"
    EOF

    runHook postInstall
  '';

  meta = {
    description = "XInput 1.3 guitar shim DLL for Guitar Hero games under Wine";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
}
