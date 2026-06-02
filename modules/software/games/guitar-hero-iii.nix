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

  useGeProton = cfg.proton == "ge-proton";

  # umu PROTONPATH: the codename "GE-Proton" (umu downloads/runs it in the sniper
  # container), or the packaged proton-cachyos install dir for host-native runs.
  protonPath =
    if useGeProton then
      "GE-Proton"
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
    lsfgVkEnable = cfg.lsfgVk.enable;
  };
in
{
  options.software.games.${gameId} = mkProtonCachyosOptions {
    command = "gh3";
    desktopName = "Guitar Hero III";
    # GH3 is 32-bit: its GPU drivers and fonts only resolve inside umu's sniper
    # container, which proton-cachyos (host-native, missing libunwind in sniper)
    # can't run in. GE-Proton is built for sniper, so use it here.
    proton = "ge-proton";
    env = [
      "WINEDLLOVERRIDES=xinput1_3=n,b"
      "vblank_mode=0"
    ];
  };

  config = lib.mkIf (!(builtins.elem gameId config.software.games.exclude)) {
    environment.systemPackages = [
      launcher
    ]
    # Only pull in proton-cachyos when a game actually uses it.
    ++ lib.optionals (cfg.proton == "cachyos") [ protonCachyos ];
  };
}
