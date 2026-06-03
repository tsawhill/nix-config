{
  config,
  pkgs,
  lib,
  ...
}:

let
  gameId = "ps3RockBand";
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
    command = "rock-band-ps3";
    desktopName = "Rock Band (PS3)";
    gamePath = "Rock Band (USA).iso";
  };

  config = lib.mkIf (!(builtins.elem gameId config.software.games.exclude)) {
    environment.systemPackages = [ launcher ];
  };
}
