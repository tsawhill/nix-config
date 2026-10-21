{
  lib,
  stdenvNoCC,
  fetchurl,
  gnutar,
  zstd,
  version ? "latest",
}:

let
  # Upstream split the package: proton-cachyos-native runs host-native, while
  # proton-cachyos-slr is built against the Steam Linux Runtime. umu always
  # launches inside a pressure-vessel container, so the -slr flavour is the one
  # that applies here; the plain "proton-cachyos" package no longer exists.
  # CachyOS's repo only keeps the current build; older ones 404. Version and
  # sha256 come from the %VERSION%/%SHA256SUM% entries in its cachyos.db.
  latestVersion = {
    packageVersion = "11.0.20261015-1";
    sha256 = "68415114f2bd452b7d99ca58d663203a9c944db09ec4d1ffbfc7a7d0aab12fda";
  };
  knownVersions = {
    latest = latestVersion;
    "11.0.20261015-1" = latestVersion;
  };
  selectedVersion =
    knownVersions.${version} or (throw "Unsupported proton-cachyos version: ${version}");

  toolDir = "proton-cachyos-slr";
in
stdenvNoCC.mkDerivation rec {
  pname = "proton-cachyos";
  version = selectedVersion.packageVersion;

  # Steam's NixOS module reads this output via extraCompatPackages. $out keeps
  # the command-line wrapper and the legacy path used by existing UMU launchers.
  outputs = [
    "out"
    "steamcompattool"
  ];

  src = fetchurl {
    url = "https://cdn77.cachyos.org/repo/x86_64/cachyos/proton-cachyos-slr-1%3A${selectedVersion.packageVersion}-x86_64.pkg.tar.zst";
    inherit (selectedVersion) sha256;
  };

  nativeBuildInputs = [
    gnutar
    zstd
  ];

  unpackPhase = ''
    runHook preUnpack
    tar --zstd -xf "$src"
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/share/steam/compatibilitytools.d" "$steamcompattool"
    cp -a usr/share/steam/compatibilitytools.d/${toolDir}/. "$steamcompattool/"
    ln -s "$steamcompattool" "$out/share/steam/compatibilitytools.d/${toolDir}"
    cat > "$out/bin/proton-cachyos" <<EOF
    #!/bin/sh
    exec "$steamcompattool/proton" "\$@"
    EOF
    chmod +x "$out/bin/proton-cachyos"

    runHook postInstall
  '';

  # The -slr build's binaries and scripts are meant to resolve their interpreter
  # and libraries inside the Steam Runtime container, not from the host nix
  # store, so leave them untouched -- same reasoning as proton-ge.nix.
  dontConfigure = true;
  dontBuild = true;
  dontPatchShebangs = true;
  dontStrip = true;
  dontPatchELF = true;

  meta = {
    description = "CachyOS Proton compatibility tool (Steam Linux Runtime build)";
    homepage = "https://github.com/CachyOS/proton-cachyos";
    license = lib.licenses.unfreeRedistributable;
    mainProgram = "proton-cachyos";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
