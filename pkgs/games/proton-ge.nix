{
  lib,
  stdenvNoCC,
  fetchurl,
  version ? "10-34",
}:

let
  # GE-Proton release tarball sha512 sums (from each release's .sha512sum).
  knownVersions = {
    "8-32" = "8fbdd675daca620c257da8d3565cf234594a2db36da6acbd69597bd43eaf582768279a97042cf2e9144b6a3f34032a97dcf3d9d90b1a74699ee48a94a4c5cfe3";
    "9-25" = "8fbfd40e72f72f9bbbf1349af2bd0bd98eafd62d95e5c19fd86c58f615c69b8e61b4cbf640c049c3394285df23976992c4ad79b4912b68db964a37df178a3ae9";
    "10-34" = "9fd0b2cfbd501c0b5c892239c392c7283a029b5e5d5a77d3f85b0ce190d555456241a18eebca16b53f094b403499201c13550a3f0b9b365e1a5eb5737cbb7303";
  };
  sha512 =
    knownVersions.${version} or (throw "Unsupported GE-Proton version: ${version}");
in
stdenvNoCC.mkDerivation {
  pname = "proton-ge";
  version = "GE-Proton${version}";

  src = fetchurl {
    url = "https://github.com/GloriousEggroll/proton-ge-custom/releases/download/GE-Proton${version}/GE-Proton${version}.tar.gz";
    inherit sha512;
  };

  # GE-Proton ships prebuilt binaries meant to run inside the Steam Runtime
  # sniper container, so leave its shebangs/ELFs untouched -- the container, not
  # the host nix store, provides their interpreter and libraries.
  dontConfigure = true;
  dontBuild = true;
  dontPatchShebangs = true;
  dontStrip = true;
  dontPatchELF = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    # The tarball's top-level GE-Proton${version}/ dir is the source root, so the
    # build is already inside it; copy its contents into $out.
    cp -a . "$out/"
    runHook postInstall
  '';

  meta = {
    description = "GloriousEggroll's Proton-GE compatibility tool (pinned ${version})";
    homepage = "https://github.com/GloriousEggroll/proton-ge-custom";
    license = lib.licenses.unfreeRedistributable;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
