{ self, ... }:
{
  imports = [
    ./base
    "${self}/modules/software/services/acme.nix"
  ];
  my.secrets = {
    sshclientkey.acme-nix.enable = true;
    acme_env.enable = true;
  };
  networking.hostName = "acme-nix";
}
