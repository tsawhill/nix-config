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
      # inputs.ags.homeManagerModules.default
      # ./ags

      inputs.hyprpanel.homeManagerModules.hyprpanel
      ./hypr

      inputs.nixvim.homeManagerModules.nixvim
      ./nixvim

      ./foot
      ./fish
      ./zsh
      ./appearance-gtk
      ./xdg
    ];
    home.sessionVariables = {
      EDITOR = "nvim";
    };

    # The state version is required and should stay at the version you
    # originally installed.
    home.stateVersion = "24.11";
  };
}
