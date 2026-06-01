{
  lib,
  stdenvNoCC,
  fetchurl,
  gnutar,
  python3,
  zstd,
  version ? "latest",
}:

let
  latestVersion = {
    packageVersion = "11.0.20260506-2";
    sha256 = "e85076c9f06bb08a637d8f90af425b5c7424ccc8e596408ba6faced9b83aff50";
  };
  knownVersions = {
    latest = latestVersion;
    "11.0.20260506-2" = latestVersion;
  };
  selectedVersion =
    knownVersions.${version}
      or (throw "Unsupported proton-cachyos version: ${version}");
in
stdenvNoCC.mkDerivation rec {
  pname = "proton-cachyos";
  version = selectedVersion.packageVersion;

  src = fetchurl {
    url = "https://cdn77.cachyos.org/repo/x86_64/cachyos/proton-cachyos-1%3A${selectedVersion.packageVersion}-x86_64.pkg.tar.zst";
    inherit (selectedVersion) sha256;
  };

  nativeBuildInputs = [
    gnutar
    python3
    zstd
  ];

  unpackPhase = ''
    runHook preUnpack
    tar --zstd -xf "$src"
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/share/steam/compatibilitytools.d"
    cp -a usr/share/steam/compatibilitytools.d/proton-cachyos "$out/share/steam/compatibilitytools.d/"
    patchShebangs "$out/share/steam/compatibilitytools.d/proton-cachyos/proton"
    ln -s "$out/share/steam/compatibilitytools.d/proton-cachyos/proton" "$out/bin/proton-cachyos"

    runHook postInstall
  '';

  dontConfigure = true;
  dontBuild = true;

  meta = {
    description = "CachyOS Proton compatibility tool";
    homepage = "https://github.com/CachyOS/proton-cachyos";
    license = lib.licenses.unfreeRedistributable;
    mainProgram = "proton-cachyos";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
