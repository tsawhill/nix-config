{ config, lib, ... }:

let
  cfg = config.my.secrets.sshclientkey.laptop-nix-taylor;
in
{
  options.my.secrets.sshclientkey.laptop-nix-taylor = {
    enable = lib.mkEnableOption "SSH client key for taylor on laptop-nix";
  };

  config = lib.mkIf cfg.enable {
    sops.secrets."id_ed25519" = {
      sopsFile = ./laptop-nix-taylor.yaml;
      path = "/home/taylor/.ssh/id_ed25519";
      owner = "taylor";
      group = "root";
      mode = "0600";
    };
    sops.secrets."id_ed25519_pub" = {
      sopsFile = ./laptop-nix-taylor.yaml;
      path = "/home/taylor/.ssh/id_ed25519.pub";
      owner = "taylor";
      group = "root";
      mode = "0644";
    };
  };
}
