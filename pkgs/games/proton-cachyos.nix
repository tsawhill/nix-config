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
    packageVersion = "11.0.20260521-3";
    sha256 = "088a56cfa6ebf8b305fef3e7b25c267d5a17e1cdc6429300197358c2b643dce8";
  };
  knownVersions = {
    latest = latestVersion;
    "11.0.20260521-3" = latestVersion;
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

    # The CachyOS package targets a CachyOS host and omits the runtime
    # requirement, so umu runs it bare on the host ("runtime host") with no
    # Steam Runtime container. That leaves 32-bit games unable to reach the GPU
    # driver and missing fonts. Declare the sniper (steamrt3) requirement so umu
    # runs it inside pressure-vessel, the same way GE-Proton does.
    sed -i 's|"commandline"|"require_tool_appid" "1628350"\n  "commandline"|' \
      "$out/share/steam/compatibilitytools.d/proton-cachyos/toolmanifest.vdf"
    cat > "$out/bin/proton-cachyos" <<EOF
    #!/bin/sh
    exec "$out/share/steam/compatibilitytools.d/proton-cachyos/proton" "\$@"
    EOF
    chmod +x "$out/bin/proton-cachyos"

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
