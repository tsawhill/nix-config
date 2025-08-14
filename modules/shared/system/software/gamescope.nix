{ pkgs-gamescope, pkgs, ... }:
{
  environment.systemPackages = [
    # pkgs-gamescope.gamescope
    pkgs.gamescope_git
  ];
}
