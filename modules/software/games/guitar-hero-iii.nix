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
    gamescopeMode =
      if cfg.gamescope.mode == null then
        config.software.games.gamescope.mode
      else
        cfg.gamescope.mode;
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
    command = "gh3";
    desktopName = "Guitar Hero III";
    # GH3 is 32-bit: its GPU drivers and fonts only resolve inside umu's sniper
    # container, which proton-cachyos (host-native, missing libunwind in sniper)
    # can't run in. GE-Proton is built for sniper, so use it here, pinned.
    proton = "ge-proton";
    protonVersion = "9-25";
    env = [
      "WINEDLLOVERRIDES=xinput1_3=n,b"
      "vblank_mode=0"
      "PULSE_LATENCY_MSEC=60"
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
