{
  pkgs,
  inputs,
  home-manager,
  ...
}:
{
  imports = [ inputs.home-manager.nixosModules.default ];

  home-manager.backupFileExtension = "bak";
  home-manager.users.taylor = {
    imports = [
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
    programs.bash.enable = true; # Needed for session variables

    # The state version is required and should stay at the version you
    # originally installed.
    home.stateVersion = "24.11";
  };
}
