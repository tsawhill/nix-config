{ self, ... }:
{
  imports = [
    ./base
    "${self}/modules/software/services/authentik.nix"
  ];
  networking.hostName = "authentik-nix";
}
