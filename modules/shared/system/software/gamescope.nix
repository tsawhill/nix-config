{ pkgs-gamescope, pkgs, ... }:
{
  # environment.systemPackages = [
  #   # pkgs-gamescope.gamescope
  #   pkgs.gamescope_git
  # ];
  programs.gamescope = {
    enable = true;
    package = pkgs.gamescope_git.overrideAttrs (_: {
      NIX_CFLAGS_COMPILE = [ "-fno-fast-math" ];
    });
  };
}
