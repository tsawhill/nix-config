{ lib, pkgs }:

let
  version = "1.3.0";
in
pkgs.appimageTools.wrapType2 {
  pname = "yarc-launcher";
  inherit version;

  src = pkgs.fetchurl {
    url = "https://github.com/YARC-Official/YARC-Launcher/releases/download/v${version}/YARC.Launcher_${version}_amd64.AppImage";
    sha256 = "40e6e72370ed81f899f4660139ba076ad99d131bcabdca76499a3dceebb5e556";
  };

  meta = {
    description = "The YARC (Yet Another Rhythm Company) launcher";
    homepage = "https://github.com/YARC-Official/YARC-Launcher";
    license = lib.licenses.unfreeRedistributable;
    platforms = [ "x86_64-linux" ];
    mainProgram = "yarc-launcher";
  };
}
