{
  config,
  pkgs,
  lib,
  ...
}:

let
  gameId = "iw4x";
  launcherId = "iw4xLauncher";
  mkProtonCachyosOptions = import ./lib/mk-proton-cachyos-options.nix { inherit lib; };

  mkLauncher =
    cfg:
    let
      protonCachyos = pkgs.callPackage ../../../pkgs/games/proton-cachyos.nix {
        version = cfg.protonVersion;
      };

      useGeProton = cfg.proton == "ge-proton";

      geProton = pkgs.callPackage ../../../pkgs/games/proton-ge.nix {
        version = cfg.protonVersion;
      };

      protonPath =
        if useGeProton then
          (if cfg.protonVersion == "latest" then "GE-Proton" else "${geProton}")
        else
          "${protonCachyos}/share/steam/compatibilitytools.d/proton-cachyos";
    in
    {
      package = pkgs.callPackage ../../../pkgs/games/mk-proton-cachyos-game.nix { } {
        inherit (cfg)
          desktopName
          exePath
          prefixPath
          gamescopeArgs
          env
          ;
        inherit protonPath;
        name = cfg.command;
        gamescopeResolutions =
          if cfg.gamescope.resolutions == null then
            config.software.games.gamescope.resolutions
          else
            cfg.gamescope.resolutions;
        lsfgVkEnable = cfg.lsfgVk.enable;
      };

      protonPackage = protonCachyos;
    };

  gameCfg = config.software.games.${gameId};
  launcherCfg = config.software.games.${launcherId};

  gameLauncher = mkLauncher gameCfg;
  configLauncher = mkLauncher launcherCfg;
in
{
  options.software.games.${gameId} = mkProtonCachyosOptions {
    command = "iw4x";
    desktopName = "IW4x";
    exePath = "/mnt/gameSSD/Games/Call of Duty/IW4X/iw4x.exe";
    proton = "ge-proton";
    protonVersion = "10-34";
    lsfgVkEnable = config.software.games.lsfgVk.enable;
  };

  options.software.games.${launcherId} = mkProtonCachyosOptions {
    command = "iw4x-launcher";
    desktopName = "IW4x Launcher";
    exePath = "/mnt/gameSSD/Games/Call of Duty/IW4X/iw4x-launcher.exe";
    proton = "ge-proton";
    protonVersion = "10-34";
    gamescopeResolutions = [ ];
  };

  config = lib.mkMerge [
    (lib.mkIf (!(builtins.elem gameId config.software.games.exclude)) {
      environment.systemPackages =
        [
          gameLauncher.package
        ]
        ++ lib.optionals (gameCfg.proton == "cachyos") [ gameLauncher.protonPackage ];
    })
    (lib.mkIf (!(builtins.elem launcherId config.software.games.exclude)) {
      environment.systemPackages =
        [
          configLauncher.package
        ]
        ++ lib.optionals (launcherCfg.proton == "cachyos") [ configLauncher.protonPackage ];
    })
  ];
}
