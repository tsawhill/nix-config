{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:
let
  cfg = config.software.apps.gaming;
  protonGe = pkgs.callPackage ../../../../pkgs/games/proton-ge.nix { };
  protonGeVersions = map (
    version: pkgs.callPackage ../../../../pkgs/games/proton-ge.nix { inherit version; }
  ) protonGe.supportedVersions;
  protonCachyos = pkgs.callPackage ../../../../pkgs/games/proton-cachyos.nix { };
  protonDefault = pkgs.callPackage ../../../../pkgs/games/proton-default.nix {
    protonPath = protonGe.steamcompattool;
  };
in
{
  imports = [ ../../guitars ];

  options.software.apps.gaming = {
    enable = lib.mkEnableOption "gaming tools and launchers";
    lsfgVk.enable = lib.mkEnableOption "lsfg-vk frame generation layer";
  };

  config = lib.mkIf cfg.enable {
    programs.steam = {
      enable = true;
      remotePlay.openFirewall = true;
      dedicatedServer.openFirewall = true;
      localNetworkGameTransfers.openFirewall = true;
      extraPackages = lib.optionals cfg.lsfgVk.enable [ pkgs.lsfg-vk ];
      extraCompatPackages = [ protonCachyos ] ++ protonGeVersions;
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
