{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
}:

# Upstream's static web build; nixpkgs only packages the Flutter desktop app.
stdenvNoCC.mkDerivation rec {
  pname = "gopeed-web";
  version = "2.0.0-beta.3";

  src = fetchurl {
    url = "https://github.com/GopeedLab/gopeed/releases/download/v${version}/gopeed-web-v${version}-linux-amd64.zip";
    sha256 = "230f703d8147df28b68c162c4398e12d8e57412d43584f7312fa3532c2bd3c8e";
  };

  nativeBuildInputs = [ unzip ];

  installPhase = ''
    runHook preInstall
    install -Dm755 gopeed "$out/bin/gopeed-web"
    runHook postInstall
  '';

  dontConfigure = true;
  dontBuild = true;
  dontFixup = true;

  meta = {
    description = "Gopeed download manager, headless web build";
    homepage = "https://gopeed.com";
    license = lib.licenses.gpl3Only;
    platforms = [ "x86_64-linux" ];
    mainProgram = "gopeed-web";
  };
}
