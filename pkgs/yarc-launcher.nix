{ lib, pkgs }:

let
  version = "1.2.0";
in
pkgs.appimageTools.wrapType2 {
  pname = "yarc-launcher";
  inherit version;

  src = pkgs.fetchurl {
    url = "https://github.com/YARC-Official/YARC-Launcher/releases/download/v${version}/YARC.Launcher_${version}_amd64.AppImage";
    sha256 = "03m1gan1d66aafvlvcrdpj0r1k8jm66ik53lbm94yb95sh4mn5gx";
  };

  meta = {
    description = "The YARC (Yet Another Rhythm Company) launcher";
    homepage = "https://github.com/YARC-Official/YARC-Launcher";
    license = lib.licenses.unfreeRedistributable;
    platforms = [ "x86_64-linux" ];
    mainProgram = "yarc-launcher";
  };
}
