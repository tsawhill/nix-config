{...}:
{
  imports = [
    ./hardware-configuration.nix
    ./system
    ./user_definition
  ];
  system.stateVersion = "24.11";
}