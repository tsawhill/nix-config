{ config, lib, ... }:

let
  cfg = config.my.secrets.sshclientkey.acme-nix-root;
in
{
  options.my.secrets.sshclientkey.acme-nix-root = {
    enable = lib.mkEnableOption "SSH client key for root on acme-nix";
  };

  config = lib.mkIf cfg.enable {
    sops.secrets."id_ed25519" = {
      sopsFile = ./acme-nix-root.yaml;
      path = "/root/.ssh/id_ed25519";
      owner = "root";
      group = "root";
      mode = "0600";
    };
    sops.secrets."id_ed25519_pub" = {
      sopsFile = ./acme-nix-root.yaml;
      path = "/root/.ssh/id_ed25519.pub";
      owner = "root";
      group = "root";
      mode = "0644";
    };
  };
}
