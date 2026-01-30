{ self, ... }:
{
  imports = [
    ./base
    "${self}/modules/software/services/unbound.nix"
  ];
  networking.hostName = "unbound-vpn-na-nix";
}
