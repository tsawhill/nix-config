{ config, lib, ... }:

let
  cfg = config.my.secrets.sshclientkey.syncoid-pi-backup;
in
{
  options.my.secrets.sshclientkey.syncoid-pi-backup = {
    enable = lib.mkEnableOption "SSH client key for Syncoid backups to pi-backup-nix";
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.syncoid_pi_backup_id_ed25519 = {
      sopsFile = ./syncoid-pi-backup.yaml;
      key = "id_ed25519";
      owner = "syncoid";
      group = "syncoid";
      mode = "0400";
    };

    sops.secrets.syncoid_pi_backup_id_ed25519_pub = {
      sopsFile = ./syncoid-pi-backup.yaml;
      key = "id_ed25519_pub";
      owner = "syncoid";
      group = "syncoid";
      mode = "0444";
    };
  };
}
