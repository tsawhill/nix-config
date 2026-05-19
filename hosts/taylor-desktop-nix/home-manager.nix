{
  inputs,
  self,
  home-manager-input,
  nixvim-input,
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
        "${self}/modules/home-manager/gui/hypr"
        (import "${self}/pkgs/hyprcrosshair/hm-module.nix" self)
      ];
      home.stateVersion = "25.11";
      my.shell.starshipTheme = "personal";
      my.yarg.enable = true;

      my.hypr = {
        monitors.primary = "DP-1";
        monitors.secondary = "DP-2";
        gpuRecorder = {
          enable = true;
          fps = 120;
          audio.output = [
            "discord_audio.monitor"
            "game_audio.monitor"
            "desktop_audio.monitor"
          ];
          audio.input = [
            "mic_input"
          ];
        };
        wallpaperEngine = {
          enable = true;
          monitors."DP-1" = {
            wallpapers = [
              "3648098553"
              "3652040138"
              "3687714819"
            ];
            fps = 15;
            rotateInterval = "10m";
          };
          monitors."DP-2" = {
            wallpapers = [
              "3648098553"
              "3652040138"
              "3687714819"
            ];
            fps = 15;
            rotateInterval = "10m";
          };
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
