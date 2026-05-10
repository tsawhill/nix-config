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
  peerUnit = "wireguard-${wireguard.interface}-peer-${wireguard.peer.name}";
  peerService = "${peerUnit}.service";
in
{
  networking.useDHCP = lib.mkDefault true;
  networking.firewall.checkReversePath = "loose";

  networking.wireguard.interfaces = lib.mkIf wireguard.enable {
    ${wireguard.interface} = {
      ips = [ wireguard.address ];
      privateKeyFile = config.sops.secrets.pi_backup_wireguard_private_key.path;
      listenPort = wireguard.listenPort;
      mtu = 1280;
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

  systemd.services.${peerUnit} = lib.mkIf wireguard.enable {
    unitConfig.StartLimitIntervalSec = 0;
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = "15s";
    };
  };

  systemd.services."wireguard-${wireguard.interface}-dns" = lib.mkIf wireguard.enable {
    description = "Prefer VPN DNS when ${wireguard.interface} can reach home DNS";
    wants = [ peerService ];
    after = [
      "wireguard-${wireguard.interface}.service"
      peerService
    ];
    wantedBy = [ wireguardTarget ];
    unitConfig.PartOf = [ wireguardTarget ];

    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = "15s";
    };

    script = ''
      active=0
      cleanup() {
        ${pkgs.openresolv}/sbin/resolvconf -d ${wireguard.interface} >/dev/null 2>&1 || true
      }
      trap cleanup EXIT

      cleanup

      while true; do
        if ${pkgs.dnsutils}/bin/dig +time=2 +tries=1 @10.73.73.6 . NS >/dev/null 2>&1; then
          if [ "$active" -ne 1 ]; then
            printf 'nameserver 10.73.73.6\n' | ${pkgs.openresolv}/sbin/resolvconf -m 0 -x -a ${wireguard.interface}
            active=1
          fi
        else
          if [ "$active" -ne 0 ]; then
            cleanup
            active=0
          fi
        fi

        sleep 15
      done
    '';

    postStop = ''
      ${pkgs.openresolv}/sbin/resolvconf -d ${wireguard.interface} || true
    '';
  };
}
