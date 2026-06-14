{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.software.apps.gaming;
  protonDefault = pkgs.callPackage ../../../../pkgs/games/proton-default.nix { };
in
{
  options.software.apps.gaming.enable = lib.mkEnableOption "gaming tools and launchers";
  options.software.apps.gaming.lsfgVk.enable = lib.mkEnableOption "lsfg-vk frame generation layer";

  config = lib.mkIf cfg.enable {
    programs.steam = {
      enable = true;
      remotePlay.openFirewall = true;
      dedicatedServer.openFirewall = true;
      localNetworkGameTransfers.openFirewall = true;
      extraPackages = lib.optionals cfg.lsfgVk.enable [ pkgs.lsfg-vk ];
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
      extraPackages32 =
        [ pkgs.pkgsi686Linux.mangohud ]
        ++ lib.optionals cfg.lsfgVk.enable [ pkgs.pkgsi686Linux.lsfg-vk ];
    };

    services.udev = {
      packages = [ pkgs.game-devices-udev-rules ];
      extraRules = ''
        # Wine's raw HID path needs access to the MiniHost hidraw node.
        KERNEL=="hidraw*", ATTRS{idVendor}=="1209", ATTRS{idProduct}=="2882", GROUP="input", MODE="0660", TAG+="uaccess"
      '';
    };

    environment.sessionVariables = {
      # MiniHost GH Guitar controller mapping
      SDL_GAMECONTROLLERCONFIG = "03000000091200008228000001010000,MiniHost GH Guitar,platform:Linux,a:b0,b:b1,x:b3,y:b4,leftshoulder:b6,back:b10,start:b11,dpup:h0.1,dpdown:h0.4,leftx:a0,righty:a2";
    } // lib.optionalAttrs cfg.lsfgVk.enable {
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

        # Performance
        gamemode
        mangohud
        vulkan-headers

        # Streaming
        moonlight-qt
      ]
      ++ lib.optionals cfg.lsfgVk.enable [
        lsfg-vk
        vulkan-tools
      ];
  };
}
