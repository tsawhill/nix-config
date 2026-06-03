{
  config,
  pkgs,
  lib,
  ...
}:

let
  gameId = "plutonium";
  cfg = config.software.games.${gameId};
  mkProtonCachyosOptions = import ./lib/mk-proton-cachyos-options.nix { inherit lib; };

  protonCachyos = pkgs.callPackage ../../../pkgs/games/proton-cachyos.nix {
    version = cfg.protonVersion;
  };

  useGeProton = cfg.proton == "ge-proton";

  geProton = pkgs.callPackage ../../../pkgs/games/proton-ge.nix {
    version = cfg.protonVersion;
  };

  # umu PROTONPATH for "ge-proton": a pinned GE-Proton install dir (fetched at
  # build time), or the codename "GE-Proton" which umu downloads/auto-updates at
  # runtime. For "cachyos", the packaged proton-cachyos install dir (host-native).
  protonPath =
    if useGeProton then
      (if cfg.protonVersion == "latest" then "GE-Proton" else "${geProton}")
    else
      "${protonCachyos}/share/steam/compatibilitytools.d/proton-cachyos";

  launcher = pkgs.callPackage ../../../pkgs/games/mk-proton-cachyos-game.nix { } {
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
in
{
  options.software.games.${gameId} = mkProtonCachyosOptions {
    command = "plutonium";
    desktopName = "Plutonium";
    exePath = "/mnt/gameSSD/Games/Call of Duty/Plutonium/plutonium.exe";
    proton = "ge-proton";
    protonVersion = "10-34";
  };

  config = lib.mkIf (!(builtins.elem gameId config.software.games.exclude)) {
    environment.systemPackages = [
      launcher
    ]
    # Only pull in proton-cachyos when a game actually uses it.
    ++ lib.optionals (cfg.proton == "cachyos") [ protonCachyos ];
  };
}
