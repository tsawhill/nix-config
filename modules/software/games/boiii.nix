{
  config,
  pkgs,
  lib,
  ...
}:

let
  gameId = "boiii";
  steamId = "boiiiSteam";
  cfg = config.software.games.${gameId};
  steamCfg = config.software.games.${steamId};
  mkProtonCachyosOptions = import ./lib/mk-proton-cachyos-options.nix { inherit lib; };

  mkLauncher =
    cfg:
    {
      exePathOverride ? null,
    }:
    let
      exePath = if exePathOverride == null then cfg.exePath else exePathOverride;

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
          prefixPath
          gamescopeArgs
          env
          ;
        inherit exePath;
        inherit protonPath;
        name = cfg.command;
        gamescopeResolutions =
          if cfg.gamescope.resolutions == null then
            config.software.games.gamescope.resolutions
          else
            cfg.gamescope.resolutions;
        lsfgVkEnable = cfg.lsfgVk.enable;
      };

      inherit protonCachyos;
    };

  launcher = mkLauncher cfg { };
  steamLauncher = mkLauncher steamCfg {
    exePathOverride = "${steamCfg.prefixPath}/drive_c/Program Files (x86)/Steam/Steam.exe";
  };
in
{
  options.software.games.${gameId} = mkProtonCachyosOptions {
    command = "boiii";
    desktopName = "BOIII";
    exePath = "/mnt/gameSSD/Games/Call of Duty/boiii/boiii.exe";
    proton = "ge-proton";
    protonVersion = "10-34";
    lsfgVkEnable = config.software.games.lsfgVk.enable;
  };

  options.software.games.${steamId} = mkProtonCachyosOptions {
    command = "boiii-steam";
    desktopName = "BOIII Steam";
    exePath = "$HOME/Games/saves/wine/default/drive_c/Program Files (x86)/Steam/Steam.exe";
    proton = "ge-proton";
    protonVersion = "10-34";
    gamescopeResolutions = [ ];
  };

  config = lib.mkMerge [
    (lib.mkIf (!(builtins.elem gameId config.software.games.exclude)) {
      environment.systemPackages =
        [
          launcher.package
        ]
        ++ lib.optionals (cfg.proton == "cachyos") [ launcher.protonCachyos ];
    })
    (lib.mkIf (!(builtins.elem steamId config.software.games.exclude)) {
      environment.systemPackages =
        [
          steamLauncher.package
        ]
        ++ lib.optionals (steamCfg.proton == "cachyos") [ steamLauncher.protonCachyos ];
    })
  ];
}
