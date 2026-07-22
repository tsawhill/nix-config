{ pkgs, ... }:

{
  environment.systemPackages = [
    (pkgs.callPackage ../../../../pkgs/games/xinput-guitar-dll.nix { })
  ];
}
