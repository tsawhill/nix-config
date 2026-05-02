{ config, lib, ... }:

let
  wireguard = {
    enable = false;
    interface = "wg0";
    listenPort = 51820;

    address = "10.50.50.5/32";
    peer = {
      publicKey = "***REDACTED_WG_PUBKEY***";
      allowedIPs = [
        "10.73.73.0/24"
        "10.50.0.0/16"
      ];
      endpoint = "taylordnsfree.zapto.org:51820";
    };
  };
in
{
  networking.useDHCP = lib.mkDefault true;

  networking.wireguard.interfaces = lib.mkIf wireguard.enable {
    ${wireguard.interface} = {
      ips = [ wireguard.address ];
      privateKeyFile = config.sops.secrets.pi_backup_wireguard_private_key.path;
      listenPort = wireguard.listenPort;

      peers = [
        {
          inherit (wireguard.peer) publicKey allowedIPs endpoint;
          persistentKeepalive = 25;
        }
      ];
    };
  };
}
