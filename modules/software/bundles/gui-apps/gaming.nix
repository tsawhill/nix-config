{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.software.apps.gaming;
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

    # MiniHost GH Guitar controller mapping
    environment.sessionVariables = {
      SDL_GAMECONTROLLERCONFIG = "03000000091200008228000001010000,MiniHost GH Guitar,platform:Linux,a:b0,b:b1,x:b3,y:b4,leftshoulder:b6,back:b10,start:b11,dpup:h0.1,dpdown:h0.4,leftx:a0,righty:a2";
    }
    // lib.optionalAttrs cfg.lsfgVk.enable {
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

        # Mod / config tools
        protonplus
        prismlauncher
        gpu-screen-recorder

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
