{
  config,
  pkgs,
  lib,
  ...
}:

let
  gameId = "ps3GuitarHeroWorldTour";
  cfg = config.software.games.${gameId};
  mkRpcs3Options = import ./lib/mk-rpcs3-options.nix { inherit lib; };

  launcher = pkgs.callPackage ../../../pkgs/games/mk-rpcs3-game.nix { } {
    inherit (cfg)
      desktopName
      gamePath
      args
      gamescopeArgs
      env
      ;
    name = cfg.command;
    gamescopeResolutions =
      if cfg.gamescope.resolutions == null then
        config.software.games.gamescope.resolutions
      else
        cfg.gamescope.resolutions;
    lsfgVkEnable = cfg.lsfgVk.enable;
  };
in
{
  options.software.games.${gameId} = mkRpcs3Options {
    command = "gh-world-tour-ps3";
    desktopName = "Guitar Hero World Tour (PS3)";
    gamePath = "Guitar Hero World Tour (USA) (En,Fr).iso";
  };

  config = lib.mkIf (!(builtins.elem gameId config.software.games.exclude)) {
    environment.systemPackages = [ launcher ];
  };
}
