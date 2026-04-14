{ self, inputs, ... }:
{
  imports = [
    ./base
    "${self}/modules/software/services/searx.nix"
  ];
  networking.hostName = "searx-nix";
  my.secrets.searx_secret_key.enable = true;
  services.searx.package = inputs.nixpkgs-master.legacyPackages.x86_64-linux.searxng;
}
