{
  config,
  lib,
  pkgs,
  ...
}:

let
  wireguard = {
    enable = true;
    interface = "wg0";
    listenPort = 51820;

    address = "10.50.50.5/32";
    peer = {
      name = "server";
      publicKey = "***REDACTED_WG_PUBKEY***";
      allowedIPs = [
        "10.73.73.0/24"
        "10.50.0.0/16"
      ];
      endpoint = "taylordnsfree.zapto.org:51820";
    };
  };

  wireguardTarget = "wireguard-${wireguard.interface}.target";
  peerService = "wireguard-${wireguard.interface}-peer-${wireguard.peer.name}.service";
in
{
  networking.useDHCP = lib.mkDefault true;

  networking.wireguard.interfaces = lib.mkIf wireguard.enable {
    ${wireguard.interface} = {
      ips = [ wireguard.address ];
      privateKeyFile = config.sops.secrets.pi_backup_wireguard_private_key.path;
      listenPort = wireguard.listenPort;
      # Keep VPN routes as fallbacks when the Pi is directly on the same LAN.
      metric = 50000;

      peers = [
        {
          inherit (wireguard.peer)
            name
            publicKey
            allowedIPs
            endpoint
            ;
          persistentKeepalive = 25;
        }
      ];
    };
  };

  systemd.services."wireguard-${wireguard.interface}-dns" = lib.mkIf wireguard.enable {
    description = "Prefer VPN DNS when ${wireguard.interface} is active";
    requires = [ peerService ];
    after = [ peerService ];
    wantedBy = [ wireguardTarget ];
    unitConfig.PartOf = [ wireguardTarget ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      printf 'nameserver 10.73.73.6\n' | ${pkgs.openresolv}/sbin/resolvconf -m 0 -x -a ${wireguard.interface}
    '';

    postStop = ''
      ${pkgs.openresolv}/sbin/resolvconf -d ${wireguard.interface} || true
    '';
  };
}
