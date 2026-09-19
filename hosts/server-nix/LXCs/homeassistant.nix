{ self, ... }:
{
  imports = [
    ./base
    "${self}/modules/software/services/homeassistant"
  ];
  networking.hostName = "homeassistant-nix";
}
