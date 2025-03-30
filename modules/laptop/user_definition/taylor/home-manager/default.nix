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

  home-manager.users.taylor = {
    imports = [
      ./hyprland
      ./hyprpanel
    ];
  };
}

