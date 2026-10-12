{
  inputs,
  self,
  home-manager-input,
  nixvim-input,
  lib,
  ...
}:
{
  imports = [
    home-manager-input.nixosModules.default
  ];

  home-manager = {
    extraSpecialArgs = {
      inherit
        inputs
        self
        home-manager-input
        nixvim-input
        ;
    };

    users.taylor = {
      imports = [
        "${self}/modules/home-manager/bundles/all.nix"
        "${self}/modules/home-manager/bundles/gui.nix"
        "${self}/modules/home-manager/git.nix"
        "${self}/modules/home-manager/gui/hypr"
        "${self}/modules/home-manager/gui/mangohud.nix"
        "${self}/modules/home-manager/gui/vesktop.nix"
        (import "${self}/pkgs/hyprcrosshair/hm-module.nix" self)
      ];
      home.stateVersion = "26.05";
      my.nixvim.full = true;
      my.shell.starshipTheme = "personal";
      my.yarg.enable = true;

      my.hypr = {
        monitors.primary = "DP-1";
        monitors.secondary = "DP-2";
        crosshair.monitor = "primary";
        gpuRecorder = {
          enable = true;
          captureTarget = "primary";
          videoCodec = "hevc_hdr";
          # quality = "ultra";
          extraArgs = [ "-tune quality" ];
          fps = 120;
          activation.processPatterns = [
            "gamescope"
            "net[.]runelite[.]client[.]RuneLite"
            "(^|/)cs2([[:space:]]|$)"
          ];
          audio.output = [
            "discord_audio.monitor"
            "game_audio.monitor"
            "desktop_audio.monitor"
          ];
          audio.input = [
            "mic_input"
            "alsa_input.usb-MOTU_M2_M2MA072BWT-00.pro-input-0"
          ];
        };
        wallpapers = {
          enable = true;
          # e.g. monitors."DP-1".videos = [ "name.mp4" ]; (after wallpapers-sync on build-nix)
        };
      };

      systemd.user.sessionVariables = {
        AQ_DRM_DEVICES = "/dev/dri/amd-dgpu";
      };
    };

    backupFileExtension = "bak";
    useGlobalPkgs = true;
    useUserPackages = true;
  };
}
