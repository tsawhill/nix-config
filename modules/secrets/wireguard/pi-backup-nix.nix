{ config, lib, ... }:

let
  cfg = config.my.secrets.wireguard.pi-backup-nix;
in
{
  options.my.secrets.wireguard.pi-backup-nix = {
    enable = lib.mkEnableOption "WireGuard key pair for pi-backup-nix";
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.pi_backup_wireguard_private_key = {
      sopsFile = ./pi-backup-nix.yaml;
      key = "private_key";
      owner = "root";
      group = "root";
      mode = "0400";
    };

    sops.secrets.pi_backup_wireguard_public_key = {
      sopsFile = ./pi-backup-nix.yaml;
      key = "public_key";
      owner = "root";
      group = "root";
      mode = "0444";
    };
  };
}
