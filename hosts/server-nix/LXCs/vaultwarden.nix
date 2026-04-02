{ self, ... }:
{
  imports = [
    ./base
    "${self}/modules/software/services/vaultwarden.nix"
  ];
  my.secrets.vaultwarden_env.enable = true;
  networking.hostName = "vaultwarden-nix";
}
