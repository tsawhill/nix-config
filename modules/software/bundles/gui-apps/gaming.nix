{ pkgs, lib, config, ... }:
{
  options.software.apps.gaming.enable = lib.mkEnableOption "gaming tools and launchers";

  config = lib.mkIf config.software.apps.gaming.enable {
    programs.steam = {
      enable = true;
      remotePlay.openFirewall = true;
      dedicatedServer.openFirewall = true;
      localNetworkGameTransfers.openFirewall = true;
    };

    programs.gamescope = {
      enable = true;
      capSysNice = true;
      package = pkgs.gamescope.overrideAttrs (_: {
        NIX_CFLAGS_COMPILE = [ "-fno-fast-math" ];
      });
    };

    programs.gpu-screen-recorder.enable = true;

    # MiniHost GH Guitar controller mapping
    environment.sessionVariables = {
      SDL_GAMECONTROLLERCONFIG = "03000000091200008228000001010000,MiniHost GH Guitar,platform:Linux,a:b0,b:b1,x:b3,y:b4,leftshoulder:b6,back:b10,start:b11,dpup:h0.1,dpdown:h0.4,leftx:a0,righty:a2";
    };

    environment.systemPackages = with pkgs; [
      # Launchers
      heroic
      lutris
      faugus-launcher
      bolt-launcher
      boilr

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
    ];
  };
}
