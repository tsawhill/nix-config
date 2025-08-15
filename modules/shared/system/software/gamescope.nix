{ pkgs, ... }:
{
  programs.gamescope = {
    enable = true;
    package = pkgs.gamescope_git.overrideAttrs (_: {
      NIX_CFLAGS_COMPILE = [ "-fno-fast-math" ];
    });
  };
}
