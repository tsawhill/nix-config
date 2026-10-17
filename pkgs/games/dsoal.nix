{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "dsoal";
  # Upstream's CI build, bundling OpenAL Soft r10786 as dsoal-aldrv.dll.
  version = "r696";

  src = fetchurl {
    url = "https://github.com/kcat/dsoal/releases/download/archive/DSOAL_${finalAttrs.version}.zip";
    hash = "sha256-lz64MTbRErraP8ZbX13CGPqCVBXBXUlOLJeu+0qVPSQ=";
  };

  nativeBuildInputs = [ unzip ];

  # The archive asset wraps the release zip in a second zip.
  unpackPhase = ''
    runHook preUnpack
    unzip -q "$src"
    unzip -q DSOAL_${finalAttrs.version}.zip
    runHook postUnpack
  '';

  dontConfigure = true;
  dontBuild = true;

  # Only the Win32 DLLs: the games using this are 32-bit.
  installPhase = ''
    runHook preInstall

    install -Dm0644 -t "$out/share/games/dsoal" \
      DSOAL/Win32/dsound.dll \
      DSOAL/Win32/dsoal-aldrv.dll
    install -Dm0644 -t "$out/share/doc/dsoal" DSOAL/Documentation/*

    # OpenAL Soft reads alsoft.ini from beside the executable. Its dsound
    # backend would load DSOAL itself, so pin WASAPI. Wine raises any shared
    # buffer below 30 ms to 30 ms, so smaller sizes gain nothing.
    cat > "$out/share/games/dsoal/alsoft.ini" <<'EOF'
    [general]
    drivers = wasapi
    period_size = 480
    periods = 2
    EOF

    runHook postInstall
  '';

  meta = {
    description = "DirectSound-to-OpenAL DLL replacement, prebuilt with OpenAL Soft";
    homepage = "https://github.com/kcat/dsoal";
    license = with lib.licenses; [
      lgpl21Plus
      lgpl2Plus
    ];
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
