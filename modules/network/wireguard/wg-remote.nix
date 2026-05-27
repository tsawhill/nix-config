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
        };
        ipv6 = {
          method = "disabled";
        };
      };
    };
  };
}
