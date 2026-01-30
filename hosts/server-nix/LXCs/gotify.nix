{ self, ... }:
{
  imports = [
    ./base
    "${self}/modules/software/services/gotify.nix"
  ];
  networking.hostName = "gotify-nix";
}
