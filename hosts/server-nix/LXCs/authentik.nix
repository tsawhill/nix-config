{ self, ... }:
{
  imports = [
    ./base
    "${self}/modules/software/services/authentik.nix"
  ];
  my.secrets.authentik_env.enable = true;
  my.secrets.authentik_ldap_outpost.enable = true;
  networking.hostName = "authentik-nix";
}
