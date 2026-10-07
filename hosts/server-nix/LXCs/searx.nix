{ self, ... }:

{
  imports = [
    ./base
    "${self}/modules/software/services/searx.nix"
  ];
  networking.hostName = "searx-nix";
  my.secrets.searx_secret_key.enable = true;
}
