{ pkgs-gamescope, pkgs, ... }:
{
  # environment.systemPackages = [
  #   # pkgs-gamescope.gamescope
  #   pkgs.gamescope_git
  # ];
  programs.gamescope = {
    enable = true;
    package = pkgs.gamescope.overrideAttrs (_: {
      NIX_CFLAGS_COMPILE = [ "-fno-fast-math" ];
    });
  };
}
