{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.network.wg-remote;
  address = lib.head (lib.splitString "/" cfg.address);
  allowedIPs = lib.filter (ip: ip != "") (lib.splitString ";" cfg.peer.allowedIPs);
  allowedIPCount = lib.length allowedIPs;

  dnsSection = lib.optionalString (cfg.dns != null) ''
    dns=${cfg.dns};
    dns-priority=${toString cfg.dnsPriority}
  '';

  metricSection = lib.optionalString (cfg.routeMetric != null) ''
    route-metric=${toString cfg.routeMetric}
  '';

  # Keep the peer routes explicit instead of relying on NetworkManager's
  # wireguard.peer-routes default.  In particular, set the preferred source so
  # traffic to another WireGuard peer cannot inherit an address from another
  # active connection.
  peerRouteSection = lib.concatStringsSep "\n" (
    lib.imap1 (i: ip: ''
      route${toString i}=${ip}
      route${toString i}_options=table=254,src=${address}
    '') allowedIPs
  );

  sourceRouteSection = lib.optionalString cfg.sourceRouting.enable (
    lib.concatStringsSep "\n" (
      (lib.imap1 (
        i: ip:
        let
          routeIndex = allowedIPCount + i;
        in
        ''
          route${toString routeIndex}=${ip}
          route${toString routeIndex}_options=table=${toString cfg.sourceRouting.table},src=${address}
        ''
      ) allowedIPs)
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

    reconnectOnLinkChange = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Reconnect an autoconnected tunnel after resume or after an underlying
        network link comes up. This refreshes the endpoint route and handshake.
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
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
            peer-routes=false

            [wireguard-peer.${config.sops.placeholder.wg_pubkey_router_wg_remote}]
            endpoint=${cfg.peer.endpoint}
            allowed-ips=${cfg.peer.allowedIPs}
            persistent-keepalive=${cfg.peer.persistentKeepalive}

            [ipv4]
            method=manual
            address1=${cfg.address}
            ${dnsSection}${metricSection}
            ${peerRouteSection}
            ${sourceRouteSection}
            [ipv6]
            method=disabled
          '';
        };

        systemd.services.NetworkManager.restartTriggers = [
          config.sops.templates."nm-wg-remote".content
        ];
      }

      (lib.mkIf (cfg.reconnectOnLinkChange && cfg.autoconnect == "true") {
        networking.networkmanager.dispatcherScripts = [
          {
            source = pkgs.writeShellScript "wg-remote-link-change" ''
              if [ "$1" != "wg-remote" ] && [ "$2" = "up" ]; then
                ${pkgs.systemd}/bin/systemctl --no-block restart wg-remote-reconnect.service
              fi
            '';
            type = "basic";
          }
        ];

        powerManagement.resumeCommands = ''
          ${pkgs.systemd}/bin/systemctl --no-block restart wg-remote-reconnect.service
        '';

        systemd.services.wg-remote-reconnect = {
          description = "Reconnect wg-remote after an underlying network change";
          after = [ "NetworkManager.service" ];
          requires = [ "NetworkManager.service" ];
          path = [ pkgs.networkmanager ];
          serviceConfig.Type = "oneshot";
          script = ''
            nmcli connection down id wg-remote >/dev/null 2>&1 || true

            if nm-online --quiet --timeout=30; then
              nmcli connection up id wg-remote
            fi
          '';
        };
      })
    ]
  );
}
