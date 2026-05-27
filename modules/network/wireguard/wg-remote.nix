{ config, lib, ... }:

let
  cfg = config.my.network.wg-remote;
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
      publicKey = lib.mkOption {
        type = lib.types.str;
        description = "Peer public key";
      };

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
  };

  config = lib.mkIf cfg.enable {
    sops.templates."nm-wg-remote-env" = {
      content = ''
        WG_REMOTE_PRIVATE_KEY=${config.sops.placeholder.wg_remote_private_key}
      '';
    };

    networking.networkmanager.ensureProfiles = {
      environmentFiles = [
        config.sops.templates."nm-wg-remote-env".path
      ];

      profiles.wg-remote = {
        connection = {
          id = "wg-remote";
          type = "wireguard";
          interface-name = "wg-remote";
          autoconnect = cfg.autoconnect;
        };
        wireguard = {
          private-key = "$WG_REMOTE_PRIVATE_KEY";
        };
        "wireguard-peer.${cfg.peer.publicKey}" = {
          endpoint = cfg.peer.endpoint;
          allowed-ips = cfg.peer.allowedIPs;
          persistent-keepalive = cfg.peer.persistentKeepalive;
        };
        ipv4 = {
          method = "manual";
          address1 = cfg.address;
        } // lib.optionalAttrs (cfg.dns != null) {
          dns = "${cfg.dns};";
          dns-priority = toString cfg.dnsPriority;
        } // lib.optionalAttrs (cfg.routeMetric != null) {
          route-metric = toString cfg.routeMetric;
        };
        ipv6 = {
          method = "disabled";
        };
      };
    };
  };
}
