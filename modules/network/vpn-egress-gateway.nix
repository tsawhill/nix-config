{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.network.vpnEgress.gateway;
  airvpn = import ./networkmanager/wireguard/airvpn-servers.nix;
  validEndpointNames = lib.filter (name: builtins.hasAttr name airvpn.servers) cfg.endpointNames;
  endpoints = map (
    name:
    let
      server = airvpn.servers.${name};
    in
    {
      inherit name;
      inherit (server) ip;
      port = airvpn.port;
    }
  ) validEndpointNames;
  initialEndpoint = if endpoints == [ ] then null else builtins.head endpoints;
  metricsDirectory = "/var/lib/prometheus-node-exporter-text-files";
  stateDirectory = "/var/lib/vpn-egress";
  controller = pkgs.writeShellScriptBin "vpn-egress-controller" ''
    exec ${pkgs.python3}/bin/python3 ${../../pkgs/vpn-egress/controller.py} "$@"
  '';
  controllerConfig = pkgs.writeText "vpn-egress-controller.json" (
    builtins.toJSON {
      interface = cfg.interfaceName;
      tunnelAddress = if cfg.tunnelAddress == null then "" else cfg.tunnelAddress;
      peerPublicKey = if cfg.peerPublicKey == null then "" else cfg.peerPublicKey;
      inherit endpoints;
      allowedReasons = [
        "startup"
        "tunnel-unhealthy"
        "searx-startpage-blocked"
        "low-download-speed"
      ];
      remoteAllowedReasons = lib.unique (
        lib.concatMap (trigger: trigger.allowedReasons) cfg.remoteTriggers
      );
      inherit (cfg)
        cooldownSeconds
        blockedExitTtlSeconds
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
        ip = "${pkgs.iproute2}/bin/ip";
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
  tunnelIp =
    if cfg.tunnelAddress == null then "0.0.0.0" else lib.head (lib.splitString "/" cfg.tunnelAddress);
  setupRoutes = pkgs.writeShellScript "vpn-egress-routes" ''
    set -eu
    IP=${pkgs.iproute2}/bin/ip

    $IP route replace ${cfg.lanCidr} dev ${cfg.upstreamInterface} table ${toString cfg.routingTable}
    ${lib.concatMapStringsSep "\n" (route: ''
      $IP route replace ${route.cidr} via ${route.gateway} dev ${cfg.upstreamInterface} table ${toString cfg.routingTable}
    '') cfg.bypassRoutes}
    $IP route replace blackhole default metric 32760 table ${toString cfg.routingTable}
    $IP route replace default dev ${cfg.interfaceName} metric 10 table ${toString cfg.routingTable}

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
    enable = lib.mkEnableOption "a dedicated health-driven WireGuard VPN egress gateway";

    interfaceName = lib.mkOption {
      type = lib.types.str;
      default = "wg-airvpn";
    };
    tunnelAddress = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "10.128.0.2/32";
      description = "AirVPN-assigned IPv4 tunnel address from the dedicated device profile.";
    };
    peerPublicKey = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "AirVPN WireGuard peer public key from the dedicated device profile.";
    };
    privateKeyFile = lib.mkOption {
      type = lib.types.nullOr (lib.types.coercedTo lib.types.path toString lib.types.str);
      default = null;
    };
    presharedKeyFile = lib.mkOption {
      type = lib.types.nullOr (lib.types.coercedTo lib.types.path toString lib.types.str);
      default = null;
    };
    endpointNames = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "Aquila"
        "Bunda"
        "Guniibuu"
        "Imai"
        "Khambalia"
        "Maia"
        "Revati"
        "Sarin"
        "Sheratan"
        "Xamidimura"
      ];
      description = "AirVPN endpoint names used for health-driven rotation.";
    };
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
        assertion = cfg.tunnelAddress != null;
        message = "my.network.vpnEgress.gateway.tunnelAddress must come from the dedicated AirVPN profile.";
      }
      {
        assertion = cfg.peerPublicKey != null;
        message = "my.network.vpnEgress.gateway.peerPublicKey must come from the dedicated AirVPN profile.";
      }
      {
        assertion = cfg.privateKeyFile != null && cfg.presharedKeyFile != null;
        message = "VPN egress privateKeyFile and presharedKeyFile must be configured as runtime secret paths.";
      }
      {
        assertion = validEndpointNames == cfg.endpointNames && endpoints != [ ];
        message = "Every VPN egress endpointNames entry must exist in airvpn-servers.nix.";
      }
      {
        assertion = cfg.clientAddresses != [ ];
        message = "VPN egress must have at least one explicitly allowed clientAddress.";
      }
      {
        assertion =
          cfg.remoteTriggers != [ ] && lib.all (trigger: trigger.allowedReasons != [ ]) cfg.remoteTriggers;
        message = "VPN egress requires at least one restricted remote trigger with an allowed reason.";
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
              iifname "${cfg.upstreamInterface}" ip saddr ${clientSet} oifname "${cfg.interfaceName}" accept
              iifname "${cfg.interfaceName}" ip daddr ${clientSet} oifname "${cfg.upstreamInterface}" ct state established,related accept
            }

            chain postrouting {
              type nat hook postrouting priority srcnat; policy accept;
              ip saddr ${clientSet} oifname "${cfg.interfaceName}" masquerade
            }
          '';
        };
      };
      wireguard.interfaces.${cfg.interfaceName} = {
        ips = lib.optional (cfg.tunnelAddress != null) cfg.tunnelAddress;
        privateKeyFile =
          if cfg.privateKeyFile == null then "/run/missing-vpn-private-key" else cfg.privateKeyFile;
        allowedIPsAsRoutes = false;
        peers = [
          {
            publicKey = if cfg.peerPublicKey == null then "missing" else cfg.peerPublicKey;
            presharedKeyFile =
              if cfg.presharedKeyFile == null then "/run/missing-vpn-preshared-key" else cfg.presharedKeyFile;
            allowedIPs = [ "0.0.0.0/0" ];
            endpoint =
              if initialEndpoint == null then
                "127.0.0.1:1"
              else
                "${initialEndpoint.ip}:${toString initialEndpoint.port}";
            persistentKeepalive = 25;
          }
        ];
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
        "systemd-networkd.service"
      ];
      wants = [ "network-online.target" ];
      requires = [ "nftables.service" ];
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
