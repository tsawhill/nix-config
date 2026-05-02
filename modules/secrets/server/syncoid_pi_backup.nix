{ config, lib, ... }:

let
  cfg = config.my.secrets.syncoid_pi_backup;
in
{
  options.my.secrets.syncoid_pi_backup = {
    enable = lib.mkEnableOption "SSH client key for Syncoid backups to pi-backup-nix";
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.syncoid_pi_backup_id_ed25519 = {
      sopsFile = ./syncoid_pi_backup.yaml;
      owner = "syncoid";
      group = "syncoid";
      mode = "0400";
    };
  };
}
