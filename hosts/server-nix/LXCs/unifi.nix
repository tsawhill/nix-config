{ self, ... }:
{
  imports = [
    ./base
    "${self}/modules/software/services/unifi.nix"
  ];
  networking.hostName = "unifi-nix";
}
