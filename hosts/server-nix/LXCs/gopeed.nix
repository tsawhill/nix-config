{ self, ... }:
let
  # Gopeed serves the UI unauthenticated without its password, so both follow it.
  secretsProvisioned = false;
in
{
  imports = [
    ./base
    "${self}/modules/software/services/gopeed.nix"
  ];

  my.groups.download = {
    enable = true;
    members = [ "root" ];
    gid = 1001;
  };

  networking.hostName = "gopeed-nix";

  my.secrets.gopeed_env.enable = secretsProvisioned;
  my.services.gopeed.enable = secretsProvisioned;
}
