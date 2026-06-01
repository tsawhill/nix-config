{
  config,
  pkgs,
  lib,
  ...
}:

let
  gameId = "guitarHero3";
  cfg = config.software.games.${gameId};
  mkProtonCachyosOptions = import ./lib/mk-proton-cachyos-options.nix { inherit lib; };

  protonCachyos = pkgs.callPackage ../../../pkgs/games/proton-cachyos.nix {
    version = cfg.protonVersion;
  };

  launcher = pkgs.callPackage ../../../pkgs/games/mk-proton-cachyos-game.nix {
    inherit protonCachyos;
  } {
    inherit (cfg)
      desktopName
      exePath
      prefixPath
      gamescopeArgs
      env
      ;
    name = cfg.command;
  };
in
{
  options.software.games.${gameId} = mkProtonCachyosOptions {
    command = "gh3";
    desktopName = "Guitar Hero III";
    env = {
      DISABLE_LSFG = "0";
      WINEDLLOVERRIDES = "xinput1_3=n,b";
      vblank_mode = "0";
    };
  };

  config = lib.mkIf (!(builtins.elem gameId config.software.games.exclude)) {
    environment.systemPackages = [
      protonCachyos
      launcher
    ];
  };
}
