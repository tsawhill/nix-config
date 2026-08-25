{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.network.vpnEgress.client;
  metricsDirectory = "/var/lib/prometheus-node-exporter-text-files";
  stateDirectory = "/var/lib/searx-vpn-watchdog";
  watchdog = pkgs.writeShellScriptBin "searx-vpn-watchdog" ''
    exec ${pkgs.python3}/bin/python3 ${../../pkgs/vpn-egress/searx_watchdog.py} "$@"
  '';
  watchdogConfig = pkgs.writeText "searx-vpn-watchdog.json" (
    builtins.toJSON {
      ssh = "${pkgs.openssh}/bin/ssh";
      systemctl = "${pkgs.systemd}/bin/systemctl";
      journalctl = "${pkgs.systemd}/bin/journalctl";
      identityFile = cfg.identityFile;
      gateway = "root@${if cfg.gatewayHost == null then "missing" else cfg.gatewayHost}";
      canaryUrl = cfg.canaryUrl;
      inherit (cfg)
        canaryTimeoutSeconds
        rotationTimeoutSeconds
        incidentAttempts
        cooldownSeconds
        restartSettleSeconds
        incidentBackoffSeconds
        ;
      stateFile = "${stateDirectory}/state.json";
      metricsFile = "${metricsDirectory}/searx-vpn-watchdog.prom";
    }
  );
in
{
  options.my.network.vpnEgress.client = {
    enable = lib.mkEnableOption "leak-proof routing through a dedicated VPN egress gateway";
    enableSearxWatchdog = lib.mkEnableOption "Startpage block detection and VPN rotation for SearxNG";
    gatewayAddress = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
    };
    gatewayHost = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
    };
    normalGateway = lib.mkOption {
      type = lib.types.str;
      default = "10.73.73.1";
    };
    bypassCidrs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };
    identityFile = lib.mkOption {
      type = lib.types.str;
      default = "/etc/ssh/ssh_host_ed25519_key";
    };
    canaryUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:8080/search";
    };
    canaryTimeoutSeconds = lib.mkOption {
      type = lib.types.int;
      default = 15;
    };
    rotationTimeoutSeconds = lib.mkOption {
      type = lib.types.int;
      default = 90;
    };
    incidentAttempts = lib.mkOption {
      type = lib.types.int;
      default = 3;
    };
    cooldownSeconds = lib.mkOption {
      type = lib.types.int;
      default = 600;
    };
    restartSettleSeconds = lib.mkOption {
      type = lib.types.int;
      default = 10;
    };
    incidentBackoffSeconds = lib.mkOption {
      type = lib.types.int;
      default = 21600;
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = cfg.gatewayAddress != null;
            message = "VPN egress clients require gatewayAddress.";
          }
          {
            assertion = !cfg.enableSearxWatchdog || cfg.gatewayHost != null;
            message = "The Searx VPN watchdog requires gatewayHost.";
          }
        ];

        boot.kernel.sysctl = {
          "net.ipv6.conf.all.disable_ipv6" = 1;
          "net.ipv6.conf.default.disable_ipv6" = 1;
        };

        systemd.network.networks."50-eth0" = {
          networkConfig.IPv6AcceptRA = lib.mkForce false;
          dhcpV4Config.UseRoutes = false;
          routes = [
            {
              Destination = "0.0.0.0/0";
              Gateway = cfg.gatewayAddress;
              Metric = 10;
            }
          ]
          ++ map (cidr: {
            Destination = cidr;
            Gateway = cfg.normalGateway;
            Metric = 5;
          }) cfg.bypassCidrs;
        };
      }

      (lib.mkIf cfg.enableSearxWatchdog {
        services.prometheus.exporters.node = {
          enabledCollectors = [ "textfile" ];
          extraFlags = [ "--collector.textfile.directory=${metricsDirectory}" ];
        };
        systemd.tmpfiles.rules = [
          "d ${stateDirectory} 0700 root root - -"
          "d ${metricsDirectory} 0755 root root - -"
        ];
        systemd.services.searx-vpn-watchdog = {
          description = "Rotate VPN egress when Startpage blocks SearxNG";
          wantedBy = [ "multi-user.target" ];
          after = [
            "network-online.target"
            "searx.service"
          ];
          wants = [ "network-online.target" ];
          serviceConfig = {
            Type = "simple";
            ExecStart = "${watchdog}/bin/searx-vpn-watchdog --config ${watchdogConfig}";
            Restart = "always";
            RestartSec = "10s";
          };
        };
        environment.systemPackages = [ watchdog ];
      })
    ]
  );
}
