{ config, lib, ... }:

let
  cfg = config.my.network.wg-remote;
  address = lib.head (lib.splitString "/" cfg.address);
  allowedIPs = lib.filter (ip: ip != "") (lib.splitString ";" cfg.peer.allowedIPs);

  dnsSection = lib.optionalString (cfg.dns != null) ''
    dns=${cfg.dns};
    dns-priority=${toString cfg.dnsPriority}
  '';

  metricSection = lib.optionalString (cfg.routeMetric != null) ''
    route-metric=${toString cfg.routeMetric}
  '';

  sourceRouteSection = lib.optionalString cfg.sourceRouting.enable (
    lib.concatStringsSep "\n" (
      (lib.imap1 (i: ip: ''
        route${toString i}=${ip}
        route${toString i}_options=table=${toString cfg.sourceRouting.table},src=${address}
      '') allowedIPs)
      ++ [
        "routing-rule1=priority ${toString cfg.sourceRouting.priority} from ${address}/32 table ${toString cfg.sourceRouting.table}"
      ]
    )
  );
in
{
  options.my.network.wg-remote = {
    enable = lib.mkEnableOption "wg-remote WireGuard NM profile";

    address = lib.mkOption {
      type = lib.types.str;
      description = "Device tunnel IPv4 address with prefix (e.g. 10.50.50.2/32)";
    };

    autoconnect = lib.mkOption {
      type = lib.types.str;
      default = "false";
      description = "Whether to autoconnect";
    };

    peer = {
      endpoint = lib.mkOption {
        type = lib.types.str;
        description = "Peer endpoint (host:port)";
      };

      allowedIPs = lib.mkOption {
        type = lib.types.str;
        default = "10.50.50.0/24;";
        description = "Allowed IPs (semicolon-separated for NM)";
      };

      persistentKeepalive = lib.mkOption {
        type = lib.types.str;
        default = "25";
      };
    };

    dns = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "DNS server to use when connected (e.g. 10.73.73.6)";
    };

    dnsPriority = lib.mkOption {
      type = lib.types.int;
      default = 100;
      description = "DNS priority. Negative = exclusive (only this DNS used when active)";
    };

    routeMetric = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      description = "Route metric. Higher = lower priority, so LAN routes win";
    };

    sourceRouting = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Route traffic sourced from the wg-remote address back out the wg-remote interface.";
      };

      table = lib.mkOption {
        type = lib.types.int;
        default = 1050;
        description = "Routing table used for wg-remote source-routed replies.";
      };

      priority = lib.mkOption {
        type = lib.types.int;
        default = 1050;
        description = "Policy routing rule priority for wg-remote source-routed replies.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    sops.templates."nm-wg-remote" = {
      path = "/etc/NetworkManager/system-connections/wg-remote.nmconnection";
      owner = "root";
      group = "root";
      mode = "0600";
      content = ''
        [connection]
        id=wg-remote
        type=wireguard
        interface-name=wg-remote
        autoconnect=${cfg.autoconnect}

        [wireguard]
        private-key=${config.sops.placeholder.wg_remote_private_key}

        [wireguard-peer.${config.sops.placeholder.wg_pubkey_router_wg_remote}]
        endpoint=${cfg.peer.endpoint}
        allowed-ips=${cfg.peer.allowedIPs}
        persistent-keepalive=${cfg.peer.persistentKeepalive}

        [ipv4]
        method=manual
        address1=${cfg.address}
        ${dnsSection}${metricSection}
        ${sourceRouteSection}
        [ipv6]
        method=disabled
      '';
    };

    systemd.services.NetworkManager.restartTriggers = [
      config.sops.templates."nm-wg-remote".content
    ];
  };
}
