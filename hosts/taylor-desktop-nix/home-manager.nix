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
        monitors.primary = "DP-4";
        monitors.secondary = "DP-5";
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
          monitors."DP-4" = {
            wallpapers = [
              "3687714819"
              # "3638441224"
            ];
            fps = 15;
            rotateInterval = "10m";
          };
          monitors."DP-5" = {
            wallpapers = [
              "3687714819"
              # "3638441224"
            ];
            fps = 15;
            rotateInterval = "10m";
          };
        };
      };

      systemd.user.sessionVariables = {
        DRI_PRIME = "pci-0000_03_00_0";
        AQ_DRM_DEVICES = "/dev/dri/amd-dgpu:/dev/dri/amd-igpu";
      };
    };

    backupFileExtension = "bak";
    useGlobalPkgs = true;
    useUserPackages = true;
  };
}
