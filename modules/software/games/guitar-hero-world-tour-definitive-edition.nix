{
  config,
  pkgs,
  lib,
  ...
}:

let
  gameId = "guitarHeroWorldTourDefinitiveEdition";
  launcherId = "guitarHeroWorldTourDefinitiveEditionLauncher";
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
    command = "ghwtde";
    desktopName = "Guitar Hero World Tour: Definitive Edition";
    exePath = "/mnt/gameSSD/Games/GHWTDE/GHWT_Definitive.exe";
    proton = "ge-proton";
    protonVersion = "9-25";
    env = [
      "vblank_mode=0"
      "PULSE_LATENCY_MSEC=60"
    ];
  };

  options.software.games.${launcherId} = mkProtonCachyosOptions {
    command = "ghwtde-launcher";
    desktopName = "Guitar Hero World Tour: Definitive Edition Launcher";
    exePath = "/mnt/gameSSD/Games/GHWTDE/GHWT_Definitive_Launcher.exe";
    proton = "ge-proton";
    protonVersion = "9-25";
    env = [
      "vblank_mode=0"
      "PULSE_LATENCY_MSEC=60"
    ];
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
