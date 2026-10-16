{ lib, pkgs, ... }:
let
  mkYarg =
    channel: command: desktopName:
    let
      yarg = pkgs.callPackage ../../../../pkgs/games/yarg.nix { inherit channel; };
    in
    {
      inherit command desktopName;
      category = "YARG";
      # Fetches song-source icons, genre maps and translations.
      network.enable = lib.mkDefault true;
      env = [ "DISABLE_MANGOHUD=1" ];
      runner.native.command = lib.getExe yarg;
    };
in
{
  software.games.entries = {
    yarg = mkYarg "stable" "yarg" "YARG";
    yargNightly = mkYarg "nightly" "yarg-nightly" "YARG Nightly";
  };
}
