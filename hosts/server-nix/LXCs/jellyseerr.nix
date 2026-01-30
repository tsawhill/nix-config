{ self, ... }:
{
  imports = [
    ./base
    "${self}/modules/software/services/jellyseerr.nix"
  ];
  networking.hostName = "jellyseerr-nix";
}
