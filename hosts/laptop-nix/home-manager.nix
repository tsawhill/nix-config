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
      home.stateVersion = "25.11";
    };

    users.taylor = {
      imports = [
        "${self}/modules/home-manager/bundles/all.nix"
        "${self}/modules/home-manager/bundles/gui.nix"
        "${self}/modules/home-manager/gui/hypr"
      ];
      home.stateVersion = "25.11";
      my.shell.starshipTheme = "personal";
      my.hypr.layout = "laptop";
      my.hypr.monitors.framework16.enable = true;
      my.hypr.gpuRecorder.enable = true;

      my.hypr.wallpaperEngine = {
        enable = true;
        monitors."eDP-1" = {
          wallpapers = [
            "3272204393"
            "1132505365"
            "2784382079"
          ];
          rotateInterval = "10m";
          fps = 30;
        };
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
