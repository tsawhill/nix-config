{ config, lib, ... }:

let
  cfg = config.my.secrets.wireguard.networking-vpn-in-nix.wg-remote-server;
in
{
  options.my.secrets.wireguard.networking-vpn-in-nix.wg-remote-server = {
    enable = lib.mkEnableOption "WireGuard private key for the wg-remote server on networking-vpn-in-nix";
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.wg_remote_server_private_key = {
      sopsFile = ./wg-remote-server.yaml;
      key = "private_key";
      owner = "root";
      group = "root";
      mode = "0400";
    };
  };
}
