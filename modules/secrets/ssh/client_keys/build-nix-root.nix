{ config, lib, ... }:

let
  cfg = config.my.secrets.sshclientkey.build-nix-root;
in
{
  options.my.secrets.sshclientkey.build-nix-root = {
    enable = lib.mkEnableOption "SSH client key for root on build-nix";
  };

  config = lib.mkIf cfg.enable {
    sops.secrets."id_ed25519" = {
      sopsFile = ./build-nix-root.yaml;
      path = "/root/.ssh/id_ed25519";
      owner = "root";
      group = "root";
      mode = "0600";
    };
    sops.secrets."id_ed25519_pub" = {
      sopsFile = ./build-nix-root.yaml;
      path = "/root/.ssh/id_ed25519.pub";
      owner = "root";
      group = "root";
      mode = "0644";
    };
  };
}
