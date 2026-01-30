{ self, ... }:
{
  imports = [
    ./base
    "${self}/modules/software/services/vaultwarden.nix"
  ];
  networking.hostName = "vaultwarden-nix";
}
