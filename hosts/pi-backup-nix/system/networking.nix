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

  pubkeyPath = config.sops.secrets.wg_pubkey_router_wg_remote.path;
in
{
  networking.useDHCP = lib.mkDefault true;
  networking.firewall.checkReversePath = "loose";

  my.secrets.wireguard.pubkeys.enable = true;

  networking.useNetworkd = true;

  systemd.network.netdevs."50-${wireguard.interface}" = lib.mkIf wireguard.enable {
    netdevConfig = {
      Name = wireguard.interface;
      Kind = "wireguard";
      MTUBytes = "1280";
    };
    wireguardConfig = {
      PrivateKeyFile = config.sops.secrets.pi_backup_wireguard_private_key.path;
      ListenPort = wireguard.listenPort;
    };
    wireguardPeers = [
      {
        PublicKeyFile = pubkeyPath;
        AllowedIPs = wireguard.peer.allowedIPs;
        Endpoint = wireguard.peer.endpoint;
        PersistentKeepalive = 25;
      }
    ];
  };

  systemd.network.networks."50-${wireguard.interface}" = lib.mkIf wireguard.enable {
    matchConfig.Name = wireguard.interface;
    address = [ wireguard.address ];
    routes = [
      { Destination = "10.73.73.0/24"; Metric = 50000; }
      { Destination = "10.50.0.0/16"; Metric = 50000; }
    ];
  };

  systemd.services."wireguard-${wireguard.interface}-dns" = lib.mkIf wireguard.enable {
    description = "Prefer VPN DNS when ${wireguard.interface} can reach home DNS";
    after = [
      "systemd-networkd.service"
    ];
    wants = [ "systemd-networkd.service" ];
    wantedBy = [ "multi-user.target" ];

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
