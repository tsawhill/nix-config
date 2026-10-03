{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:
let
  cfg = config.software.apps.gaming;
  mkProtonGe = args: pkgs.callPackage ../../../../pkgs/games/proton-ge.nix args;
  mkProtonCachyos = args: pkgs.callPackage ../../../../pkgs/games/proton-cachyos.nix args;
  protonGe = mkProtonGe { };
  protonCachyos = mkProtonCachyos { };
  # Game launchers reference their own pinned Proton by store path, so only
  # the defaults plus explicitly requested versions need to go to Steam.
  steamCompatTools = lib.unique (
    [
      protonCachyos
      protonGe
    ]
    ++ map (version: mkProtonGe { inherit version; }) cfg.proton.extraGeVersions
    ++ map (version: mkProtonCachyos { inherit version; }) cfg.proton.extraCachyosVersions
  );
  protonDefault = pkgs.callPackage ../../../../pkgs/games/proton-default.nix {
    protonPath = protonGe.steamcompattool;
  };
in
{
  imports = [ ../../guitars ];

  options.software.apps.gaming = {
    enable = lib.mkEnableOption "gaming tools and launchers";
    lsfgVk.enable = lib.mkEnableOption "lsfg-vk frame generation layer";

    proton = {
      extraGeVersions = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ "10-34" ];
        description = "Older GE-Proton versions to offer in Steam besides the pinned default.";
      };

      extraCachyosVersions = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Older proton-cachyos versions to offer in Steam besides the pinned default.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    programs.steam = {
      enable = true;
      package = pkgs.steam.override {
        # Inherited by Steam's native and Proton games. Only playback is routed
        # by WirePlumber; this does not opt games into low-latency buffering.
        extraEnv = {
          PIPEWIRE_PROPS = "nix.game-audio=true";
          PULSE_PROP = "nix.game-audio=true";
        }
        // lib.optionalAttrs (cfg.steamIgnoredGuitarDevices != [ ]) {
          # mk-game-launcher removes this filter so launched games see guitars.
          SDL_GAMECONTROLLER_IGNORE_DEVICES = lib.concatStringsSep "," (
            lib.unique cfg.steamIgnoredGuitarDevices
          );
        };
      };
      remotePlay.openFirewall = true;
      dedicatedServer.openFirewall = true;
      localNetworkGameTransfers.openFirewall = true;
      extraPackages = lib.optionals cfg.lsfgVk.enable [ pkgs.lsfg-vk ];
      extraCompatPackages = steamCompatTools;
    };

    programs.gamescope = {
      enable = true;
      capSysNice = false; # gamescope's sandboxing is too aggressive for some games, e.g. steam
      package = pkgs.gamescope.overrideAttrs (_: {
        NIX_CFLAGS_COMPILE = [ "-fno-fast-math" ];
      });
    };

    programs.gpu-screen-recorder.enable = true;

    hardware.graphics = {
      enable = true;
      enable32Bit = true;
      # MangoHud's Vulkan layer must be on the host driver path (both bitnesses)
      # for pressure-vessel to import it into umu/Proton containers; it stays
      # dormant unless MANGOHUD=1. systemPackages alone doesn't reach the
      # in-container loader. GHWTDE is 32-bit, so the i686 layer is required.
      extraPackages = [ pkgs.mangohud ] ++ lib.optionals cfg.lsfgVk.enable [ pkgs.lsfg-vk ];
      extraPackages32 = [
        pkgs.pkgsi686Linux.mangohud
      ]
      ++ lib.optionals cfg.lsfgVk.enable [ pkgs.pkgsi686Linux.lsfg-vk ];
    };

    services.udev = {
      packages = [ pkgs.game-devices-udev-rules ];
    };

    environment.sessionVariables = lib.optionalAttrs cfg.lsfgVk.enable {
      DISABLE_LSFG = "1";
    };

    environment.systemPackages =
      with pkgs;
      [
        mesa
        mesa-demos
        # Launchers
        heroic
        faugus-launcher
        (pkgs.bolt-launcher.override { jdk17 = pkgs.openjdk; })
        boilr
        (pkgs.callPackage ../../../../pkgs/yarc-launcher.nix { })

        # Couch frontends for the software.games.* library
        pegasus-frontend # declarative, non-Steam gamepad frontend
        steam-rom-manager # syncs games into Steam as categorized non-Steam shortcuts
        sgdboop # SteamGridDB artwork fetcher

        # Mod / config tools
        protonplus
        prismlauncher
        gpu-screen-recorder
        protonDefault
        wineWow64Packages.stable
        winetricks
        inputs.grimoire.packages.${pkgs.system}.default

        # Performance
        gamemode
        mangohud
        vulkan-headers

        moonlight-qt

      ]
      ++ lib.optionals cfg.lsfgVk.enable [
        lsfg-vk
        vulkan-tools
      ];
  };
}
