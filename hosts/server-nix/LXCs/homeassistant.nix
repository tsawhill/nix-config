{ self, ... }:
{
  imports = [
    ./base
    "${self}/modules/software/services/homeassistant.nix"
  ];
  networking.hostName = "homeassistant-nix";
}
