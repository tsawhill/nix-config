{ config, lib, ... }:

let
  cfg = config.my.secrets.sshclientkey.server-nix-syncoid;
in
{
  options.my.secrets.sshclientkey.server-nix-syncoid = {
    enable = lib.mkEnableOption "SSH client key for syncoid on server-nix";
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.server_nix_syncoid_id_ed25519 = {
      sopsFile = ./server-nix-syncoid.yaml;
      key = "id_ed25519";
      owner = "syncoid";
      group = "syncoid";
      mode = "0400";
    };

    sops.secrets.server_nix_syncoid_id_ed25519_pub = {
      sopsFile = ./server-nix-syncoid.yaml;
      key = "id_ed25519_pub";
      owner = "syncoid";
      group = "syncoid";
      mode = "0444";
    };
  };
}
