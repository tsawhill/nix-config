{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.network.vpnEgress.gateway;
  airvpnCfg = config.my.network.airvpn;
  endpoints = airvpnCfg.endpoints;
  metricsDirectory = "/var/lib/prometheus-node-exporter-text-files";
  stateDirectory = "/var/lib/vpn-egress";
  controller = pkgs.writeShellScriptBin "vpn-egress-controller" ''
    exec ${pkgs.python3}/bin/python3 ${../../pkgs/vpn-egress/controller.py} "$@"
  '';
  controllerConfig = pkgs.writeText "vpn-egress-controller.json" (
    builtins.toJSON {
      interface = airvpnCfg.interfaceName;
      tunnelAddress = airvpnCfg.address;
      peerPublicKey = if airvpnCfg.peerPublicKey == null then "" else airvpnCfg.peerPublicKey;
      inherit endpoints;
      remoteAllowedReasons = lib.unique (
        lib.concatMap (trigger: trigger.allowedReasons) cfg.remoteTriggers
      );
      allowedReasons = lib.unique (
        [
          "startup"
          "tunnel-unhealthy"
          "low-download-speed"
        ]
        ++ lib.concatMap (trigger: trigger.allowedReasons) cfg.remoteTriggers
      );
      inherit (cfg)
        cooldownSeconds
        blockedExitTtlSeconds
        blockedExitReasons
        maxCandidateAttempts
        maxHandshakeAgeSeconds
        healthFailuresBeforeRotation
        probeTimeoutSeconds
        publicIpUrl
        gotifyUrl
        ;
      gotifyTokenFile = if cfg.gotifyTokenFile == null then null else toString cfg.gotifyTokenFile;
      stateFile = "${stateDirectory}/state.json";
      lockFile = "${stateDirectory}/rotation.lock";
      commands = {
        wg = "${pkgs.wireguard-tools}/bin/wg";
        nmcli = "${pkgs.networkmanager}/bin/nmcli";
        curl = "${pkgs.curl}/bin/curl";
      };
    }
  );
  remoteCommand =
    trigger:
    lib.concatStringsSep " " (
      [ "${controller}/bin/vpn-egress-controller --config ${controllerConfig} remote" ]
      ++ map (reason: "--allowed-reason ${reason}") trigger.allowedReasons
    );
  clientAddresses = lib.concatStringsSep ", " cfg.clientAddresses;
  clientSet = "{ ${clientAddresses} }";
  destinationPort =
    forward: if forward.destinationPort == null then forward.port else forward.destinationPort;
  portForwardKeys = lib.concatMap (
    forward: map (protocol: "${protocol}:${toString forward.port}") forward.protocols
  ) cfg.portForwards;
  portForwardNatRules = lib.concatMapStringsSep "\n" (
    forward:
    lib.concatMapStringsSep "\n" (protocol: ''
      iifname "${airvpnCfg.interfaceName}" ${protocol} dport ${toString forward.port} dnat ip to ${forward.destinationAddress}:${toString (destinationPort forward)}
    '') forward.protocols
  ) cfg.portForwards;
  portForwardFilterRules = lib.concatMapStringsSep "\n" (
    forward:
    lib.concatMapStringsSep "\n" (protocol: ''
      iifname "${airvpnCfg.interfaceName}" oifname "${cfg.upstreamInterface}" ip daddr ${forward.destinationAddress} ${protocol} dport ${toString (destinationPort forward)} accept
    '') forward.protocols
  ) cfg.portForwards;
  tunnelIp = lib.head (lib.splitString "/" airvpnCfg.address);
  setupRoutes = pkgs.writeShellScript "vpn-egress-routes" ''
    set -eu
    IP=${pkgs.iproute2}/bin/ip

    $IP route replace ${cfg.lanCidr} dev ${cfg.upstreamInterface} table ${toString cfg.routingTable}
    ${lib.concatMapStringsSep "\n" (route: ''
      $IP route replace ${route.cidr} via ${route.gateway} dev ${cfg.upstreamInterface} table ${toString cfg.routingTable}
    '') cfg.bypassRoutes}
    $IP route replace blackhole default metric 32760 table ${toString cfg.routingTable}

    $IP rule add priority 900 from ${tunnelIp}/32 table ${toString cfg.routingTable} 2>/dev/null || true
    ${lib.concatMapStringsSep "\n" (address: ''
      $IP rule add priority 1000 from ${address}/32 table ${toString cfg.routingTable} 2>/dev/null || true
    '') cfg.clientAddresses}

    # Forwarding is enabled last. If nftables or any policy route failed to
    # install, this service exits first and the kernel remains non-forwarding.
    ${pkgs.procps}/bin/sysctl -q -w net.ipv4.ip_forward=1
  '';
  teardownRoutes = pkgs.writeShellScript "vpn-egress-routes-stop" ''
    IP=${pkgs.iproute2}/bin/ip
    ${pkgs.procps}/bin/sysctl -q -w net.ipv4.ip_forward=0
    $IP rule del priority 900 from ${tunnelIp}/32 table ${toString cfg.routingTable} 2>/dev/null || true
    ${lib.concatMapStringsSep "\n" (address: ''
      $IP rule del priority 1000 from ${address}/32 table ${toString cfg.routingTable} 2>/dev/null || true
    '') cfg.clientAddresses}
    $IP route flush table ${toString cfg.routingTable} 2>/dev/null || true
  '';
in
{
  options.my.network.vpnEgress.gateway = {
    enable = lib.mkEnableOption "health-driven gateway routing around NetworkManager AirVPN profiles";
    clientAddresses = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "LAN IPv4 addresses allowed to route through this gateway.";
    };
    remoteTriggers = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            source = lib.mkOption {
              type = lib.types.str;
              description = "Source address allowed to use this trigger key.";
            };
            publicKey = lib.mkOption {
              type = lib.types.str;
              description = "Full SSH public key for this restricted trigger client.";
            };
            allowedReasons = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              description = "Exact rotation reasons this key may request.";
            };
          };
        }
      );
      default = [ ];
      description = "Source- and key-restricted remote rotation clients.";
    };
    blockedExitReasons = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Rotation reasons which temporarily block reuse of the current public exit IP.";
    };
    portForwards = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            protocols = lib.mkOption {
              type = lib.types.listOf (
                lib.types.enum [
                  "tcp"
                  "udp"
                ]
              );
              default = [
                "tcp"
                "udp"
              ];
              description = "Transport protocols forwarded for this AirVPN port.";
            };
            port = lib.mkOption {
              type = lib.types.port;
              description = "Port assigned by AirVPN and received on the tunnel.";
            };
            destinationAddress = lib.mkOption {
              type = lib.types.str;
              description = "Authorized VPN client's LAN IPv4 address.";
            };
            destinationPort = lib.mkOption {
              type = lib.types.nullOr lib.types.port;
              default = null;
              description = "LAN destination port; defaults to the AirVPN port.";
            };
          };
        }
      );
      default = [ ];
      description = "Inbound AirVPN ports DNATed to explicitly authorized VPN clients.";
    };
    upstreamInterface = lib.mkOption {
      type = lib.types.str;
      default = "eth0";
    };
    upstreamGateway = lib.mkOption {
      type = lib.types.str;
      default = "10.73.73.1";
    };
    lanCidr = lib.mkOption {
      type = lib.types.str;
      default = "10.73.73.0/24";
    };
    bypassRoutes = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            cidr = lib.mkOption { type = lib.types.str; };
            gateway = lib.mkOption { type = lib.types.str; };
          };
        }
      );
      default = [ ];
    };
    routingTable = lib.mkOption {
      type = lib.types.int;
      default = 51820;
    };
    cooldownSeconds = lib.mkOption {
      type = lib.types.int;
      default = 600;
    };
    blockedExitTtlSeconds = lib.mkOption {
      type = lib.types.int;
      default = 86400;
    };
    maxCandidateAttempts = lib.mkOption {
      type = lib.types.int;
      default = 10;
    };
    maxHandshakeAgeSeconds = lib.mkOption {
      type = lib.types.int;
      default = 180;
    };
    healthFailuresBeforeRotation = lib.mkOption {
      type = lib.types.int;
      default = 3;
    };
    probeTimeoutSeconds = lib.mkOption {
      type = lib.types.int;
      default = 10;
    };
    publicIpUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://api.ipify.org";
    };
    gotifyUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
    };
    gotifyTokenFile = lib.mkOption {
      type = lib.types.nullOr (lib.types.coercedTo lib.types.path toString lib.types.str);
      default = null;
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = airvpnCfg.enable;
        message = "VPN egress gateway requires my.network.airvpn.enable.";
      }
      {
        assertion = airvpnCfg.peerPublicKey != null;
        message = "VPN egress gateway requires my.network.airvpn.peerPublicKey from its dedicated AirVPN profile.";
      }
      {
        assertion = endpoints != [ ];
        message = "VPN egress gateway requires at least one selected my.network.airvpn endpoint.";
      }
      {
        assertion =
          !airvpnCfg.peerRoutes && airvpnCfg.neverDefault && airvpnCfg.routeTable == cfg.routingTable;
        message = "VPN egress requires AirVPN peerRoutes = false, neverDefault = true, and the same routeTable.";
      }
      {
        assertion = cfg.clientAddresses != [ ];
        message = "VPN egress must have at least one explicitly allowed clientAddress.";
      }
      {
        assertion = lib.all (trigger: trigger.allowedReasons != [ ]) cfg.remoteTriggers;
        message = "Every VPN egress remote trigger must have an allowed reason.";
      }
      {
        assertion = lib.all (forward: forward.protocols != [ ]) cfg.portForwards;
        message = "Every VPN egress port forward must select at least one protocol.";
      }
      {
        assertion = lib.all (
          forward: builtins.elem forward.destinationAddress cfg.clientAddresses
        ) cfg.portForwards;
        message = "Every VPN egress port-forward destination must also be an authorized clientAddress.";
      }
      {
        assertion = lib.unique portForwardKeys == portForwardKeys;
        message = "VPN egress port forwards cannot reuse the same protocol and AirVPN port.";
      }
      {
        assertion = cfg.gotifyUrl != null && cfg.gotifyTokenFile != null;
        message = "VPN egress Gotify URL and token file must be configured.";
      }
    ];

    boot.kernel.sysctl = {
      "net.ipv6.conf.all.disable_ipv6" = 1;
      "net.ipv6.conf.default.disable_ipv6" = 1;
    };

    networking = {
      firewall.enable = false;
      nftables = {
        enable = true;
        tables.vpn-egress = {
          family = "inet";
          content = ''
            chain input {
              type filter hook input priority filter; policy drop;
              iifname "lo" accept
              ct state established,related accept
              ip protocol icmp accept
              ip saddr ${cfg.lanCidr} tcp dport { 22, 9100, 9558 } accept
            }

            chain forward {
              type filter hook forward priority filter; policy drop;
              iifname "${cfg.upstreamInterface}" ip saddr ${clientSet} oifname "${airvpnCfg.interfaceName}" accept
              iifname "${airvpnCfg.interfaceName}" ip daddr ${clientSet} oifname "${cfg.upstreamInterface}" ct state established,related accept
              ${portForwardFilterRules}
            }

            chain prerouting {
              type nat hook prerouting priority dstnat; policy accept;
              ${portForwardNatRules}
            }

            chain postrouting {
              type nat hook postrouting priority srcnat; policy accept;
              ip saddr ${clientSet} oifname "${airvpnCfg.interfaceName}" masquerade
            }
          '';
        };
      };
    };

    users.users.root.openssh.authorizedKeys.keys = map (
      trigger:
      ''from="${trigger.source}",restrict,command="${remoteCommand trigger}" ${trigger.publicKey}''
    ) cfg.remoteTriggers;

    services.prometheus.exporters.node = {
      enabledCollectors = [ "textfile" ];
      extraFlags = [ "--collector.textfile.directory=${metricsDirectory}" ];
    };
    systemd.tmpfiles.rules = [
      "d ${stateDirectory} 0700 root root - -"
      "d ${metricsDirectory} 0755 root root - -"
    ];

    systemd.services.vpn-egress-routes = {
      description = "Install leak-proof VPN egress policy routes";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network-online.target"
        "nftables.service"
        "NetworkManager.service"
        "NetworkManager-wait-online.service"
      ];
      wants = [ "network-online.target" ];
      requires = [
        "NetworkManager.service"
        "nftables.service"
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = setupRoutes;
        ExecStop = teardownRoutes;
      };
    };
    systemd.services.vpn-egress-initialise = {
      description = "Verify an AirVPN endpoint before forwarding client traffic";
      wantedBy = [ "multi-user.target" ];
      after = [ "vpn-egress-routes.service" ];
      requires = [ "vpn-egress-routes.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${controller}/bin/vpn-egress-controller --config ${controllerConfig} ensure";
      };
    };
    systemd.services.vpn-egress-health = {
      description = "Check AirVPN egress health and rotate unhealthy endpoints";
      after = [ "vpn-egress-initialise.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${controller}/bin/vpn-egress-controller --config ${controllerConfig} health";
        SuccessExitStatus = [ 1 ];
      };
    };
    systemd.timers.vpn-egress-health = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2m";
        OnUnitActiveSec = "1m";
        Unit = "vpn-egress-health.service";
      };
    };
    systemd.services.vpn-egress-metrics = {
      description = "Export VPN egress health for Prometheus";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${controller}/bin/vpn-egress-controller --config ${controllerConfig} metrics --output ${metricsDirectory}/vpn-egress.prom";
      };
    };
    systemd.timers.vpn-egress-metrics = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "30s";
        OnUnitActiveSec = "1m";
        Unit = "vpn-egress-metrics.service";
      };
    };

    environment.systemPackages = [ controller ];
  };
}
