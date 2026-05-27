{ config, lib, ... }:

let
  cfg = config.my.secrets.wireguard.pi-backup-nix.wg-remote;
in
{
  options.my.secrets.wireguard.pi-backup-nix.wg-remote = {
    enable = lib.mkEnableOption "WireGuard private key for wg-remote on pi-backup-nix";
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.wg_remote_private_key = {
      sopsFile = ./wg-remote.yaml;
      key = "private_key";
      owner = "root";
      group = "root";
      mode = "0400";
    };
  };
}
