{
  pkgs,
  inputs,
  home-manager,
  ...
}:
{
  imports = [
    inputs.home-manager.nixosModules.default
  ];

  home-manager.backupFileExtension = "bak";
  home-manager.users.taylor = {
    imports = [
      inputs.ags.homeManagerModules.default
      inputs.hyprpanel.homeManagerModules.hyprpanel

      ./hypr
      ./foot
      ./fish
      ./appearance-gtk
    ];
    home.sessionVariables = {
      EDITOR = "nvim";
    };

    programs.ags = {
      enable = true;
      extraPackages = with pkgs; [
        inputs.ags.packages.${system}.hyprland
        inputs.ags.packages.${system}.wireplumber
        inputs.ags.packages.${system}.battery
        inputs.ags.packages.${system}.bluetooth
        inputs.ags.packages.${system}.network
        inputs.ags.packages.${system}.notifd
        inputs.ags.packages.${system}.apps
        inputs.ags.packages.${system}.mpris
        inputs.ags.packages.${system}.powerprofiles
      ];
    };


    xdg = {
      enable = true;
      portal.config = {
        hyprland = {
          default = [ "hyprland" ];
        };
      };
      userDirs = {
        enable = true;
        extraConfig = {
          XDG_SCREENSHOTS_DIR = "/home/taylor/Pictures/Screenshots";
        };
      };
    };

    # The state version is required and should stay at the version you
    # originally installed.
    home.stateVersion = "24.11";
  };
}
