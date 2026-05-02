{ config, lib, ... }:

let
  cfg = config.my.secrets.sshclientkey.server-nix-factory;
in
{
  options.my.secrets.sshclientkey.server-nix-factory = {
    enable = lib.mkEnableOption "SSH client key for nixos-factory on server-nix";
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.server_nix_factory_id_ed25519 = {
      sopsFile = ./server-nix-factory.yaml;
      key = "id_ed25519";
      owner = "root";
      group = "root";
      mode = "0600";
    };

    sops.secrets.server_nix_factory_id_ed25519_pub = {
      sopsFile = ./server-nix-factory.yaml;
      key = "id_ed25519_pub";
      owner = "root";
      group = "root";
      mode = "0444";
    };
  };
}
