{
  config,
  pkgs,
  lib,
  ...
}:

let
  gameId = "ps3GuitarHeroVanHalen";
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
    command = "gh-van-halen-ps3";
    desktopName = "Guitar Hero: Van Halen (PS3)";
    gamePath = "Guitar Hero - Van Halen (USA) (En,Fr).iso";
  };

  config = lib.mkIf (!(builtins.elem gameId config.software.games.exclude)) {
    environment.systemPackages = [ launcher ];
  };
}
