{ self, ... }:
{
  imports = [
    ./base
    "${self}/modules/software/services/acme.nix"
  ];
  networking.hostName = "acme-nix";
}
