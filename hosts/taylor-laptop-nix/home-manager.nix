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

    users.root = {
      imports = [ "${self}/modules/home-manager/bundles/all.nix" ];
      home.stateVersion = "26.05";
      my.nixvim.full = true;
    };

    users.taylor = {
      imports = [
        "${self}/modules/home-manager/bundles/all.nix"
        "${self}/modules/home-manager/bundles/gui.nix"
        "${self}/modules/home-manager/git.nix"
        "${self}/modules/home-manager/gui/hypr"
        "${self}/modules/home-manager/gui/mangohud.nix"
        "${self}/modules/home-manager/gui/vesktop.nix"
      ];
      home.stateVersion = "26.05";
      my.nixvim.full = true;
      my.shell.starshipTheme = "personal";
      my.hypr.layout = "laptop";
      my.hypr.monitors.framework16.enable = true;
      my.hypr.gpuRecorder.enable = false;

      my.hypr.wallpapers = {
        enable = true;
        # Each listed monitor rotates through every synced video (see hypr/wallpapers.nix).
        monitors."eDP-1" = { };
      };
      wayland.windowManager.hyprland.settings.device = {
        name = "pixa3854:00-093a:0274-touchpad";
        sensitivity = 0.8;
      };
    };

    backupFileExtension = "bak";
    useGlobalPkgs = true;
    useUserPackages = true;
  };
}
