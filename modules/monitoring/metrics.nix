{
  config,
  lib,
  pkgs,
  networkTopology,
  ...
}:

let
  cfg = config.my.monitoring.metrics;
  stack = cfg.stack;
  lanDomain = networkTopology.domains.lan;

  defaultHosts = [
    "server-nix"
    "build-nix"
    "monitoring-nix"
    "local-nginx-nix"
    "adguard-nix"
    "arrs-nix"
    "authentik-nix"
    "deluge-nix"
    "gotify-nix"
    "immich-nix"
    "jellyfin-nix"
    "jellyseerr-nix"
    "llm-nix"
    "nextcloud-nix"
    "pufferpanel-nix"
    "romm-nix"
    "samba-nix"
    "searx-nix"
    "socks5-vpn-eu-nix"
    "sunshine-nix"
    "syncthing-nix"
    "unbound-vpn-na-nix"
    "unifi-nix"
    "vaultwarden-nix"
  ];

  fqdn = host: "${host}.${lanDomain}";
  mkTarget = port: host: "${fqdn host}:${toString port}";

  defaultServiceChecks = [
    { name = "Authentik"; url = "https://auth.tsawhill.org"; }
    { name = "Vaultwarden"; url = "https://vault.tsawhill.org"; }
    { name = "Immich"; url = "https://immich.tsawhill.org"; }
    { name = "Jellyfin"; url = "https://jelly.tsawhill.org"; }
    { name = "Nextcloud"; url = "https://nc.tsawhill.org"; }
    { name = "Open WebUI"; url = "https://llm.tsawhill.org"; }
    { name = "Gotify"; url = "https://gotify.tsawhill.org"; }
    { name = "Radarr"; url = "https://rad.tsawhill.org"; }
    { name = "Sonarr"; url = "https://son.tsawhill.org"; }
    { name = "Lidarr"; url = "https://lid.tsawhill.org"; }
    { name = "Prowlarr"; url = "https://pro.tsawhill.org"; }
    { name = "Jellyseerr"; url = "https://request.tsawhill.org"; }
    { name = "Unifi"; url = "https://unifi.tsawhill.org"; }
    { name = "Searx"; url = "https://searx.tsawhill.org"; }
  ];

  gatusEndpoint =
    endpoint:
    {
      interval = "1m";
      conditions = [
        "[STATUS] >= 200"
        "[STATUS] < 500"
      ];
    }
    // endpoint;

  homelabDashboard = pkgs.writeText "homelab-overview-dashboard.json" (
    builtins.toJSON {
      uid = "homelab-overview";
      title = "Homelab Overview";
      timezone = "browser";
      schemaVersion = 39;
      version = 1;
      refresh = "30s";
      tags = [
        "homelab"
        "nixos"
      ];
      time = {
        from = "now-6h";
        to = "now";
      };
      panels = [
        {
          id = 1;
          title = "Exporter Up";
          type = "stat";
          gridPos = {
            h = 6;
            w = 8;
            x = 0;
            y = 0;
          };
          datasource.uid = "prometheus";
          targets = [
            {
              refId = "A";
              expr = ''sum(up{job=~"node|systemd"}) by (job)'';
            }
          ];
        }
        {
          id = 2;
          title = "CPU Busy";
          type = "timeseries";
          gridPos = {
            h = 8;
            w = 16;
            x = 8;
            y = 0;
          };
          datasource.uid = "prometheus";
          fieldConfig.defaults.unit = "percent";
          targets = [
            {
              refId = "A";
              expr = ''100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)'';
            }
          ];
        }
        {
          id = 3;
          title = "Memory Used";
          type = "timeseries";
          gridPos = {
            h = 8;
            w = 12;
            x = 0;
            y = 8;
          };
          datasource.uid = "prometheus";
          fieldConfig.defaults.unit = "percent";
          targets = [
            {
              refId = "A";
              expr = ''100 * (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes))'';
            }
          ];
        }
        {
          id = 4;
          title = "Root Disk Used";
          type = "timeseries";
          gridPos = {
            h = 8;
            w = 12;
            x = 12;
            y = 8;
          };
          datasource.uid = "prometheus";
          fieldConfig.defaults.unit = "percent";
          targets = [
            {
              refId = "A";
              expr = ''100 * (1 - (node_filesystem_avail_bytes{mountpoint="/",fstype!~"tmpfs|overlay"} / node_filesystem_size_bytes{mountpoint="/",fstype!~"tmpfs|overlay"}))'';
            }
          ];
        }
        {
          id = 5;
          title = "Gatus Endpoint Health";
          type = "stat";
          gridPos = {
            h = 8;
            w = 24;
            x = 0;
            y = 16;
          };
          datasource.uid = "prometheus";
          targets = [
            {
              refId = "A";
              expr = "gatus_results_code";
            }
          ];
        }
      ];
    }
  );
in
{
  options.my.monitoring.metrics = {
    exporters = {
      enable = lib.mkEnableOption "Prometheus host exporters";

      openFirewall = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Open exporter scrape ports on this host.";
      };
    };

    stack = {
      enable = lib.mkEnableOption "central Grafana, Prometheus, and Gatus monitoring";

      monitoredHosts = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = defaultHosts;
        description = "Hostnames to scrape for node and systemd exporter metrics.";
      };

      serviceChecks = lib.mkOption {
        type = lib.types.listOf lib.types.attrs;
        default = defaultServiceChecks;
        description = "Gatus endpoint checks for service status.";
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.exporters.enable {
      services.prometheus.exporters.node = {
        enable = true;
        enabledCollectors = [ "systemd" ];
        openFirewall = cfg.exporters.openFirewall;
      };

      services.prometheus.exporters.systemd = {
        enable = true;
        openFirewall = cfg.exporters.openFirewall;
      };
    })

    (lib.mkIf stack.enable {
      services.prometheus = {
        enable = true;
        port = 9090;
        listenAddress = "0.0.0.0";
        retentionTime = "30d";
        globalConfig.scrape_interval = "15s";
        scrapeConfigs = [
          {
            job_name = "node";
            static_configs = [
              { targets = map (mkTarget 9100) stack.monitoredHosts; }
            ];
          }
          {
            job_name = "systemd";
            static_configs = [
              { targets = map (mkTarget 9558) stack.monitoredHosts; }
            ];
          }
          {
            job_name = "gatus";
            static_configs = [
              { targets = [ "127.0.0.1:8080" ]; }
            ];
          }
        ];
      };

      services.grafana = {
        enable = true;
        openFirewall = true;
        settings.server = {
          http_addr = "0.0.0.0";
          http_port = 3000;
          domain = "monitoring-nix.${lanDomain}";
        };
        provision = {
          enable = true;
          datasources.settings = {
            apiVersion = 1;
            datasources = [
              {
                name = "Prometheus";
                type = "prometheus";
                access = "proxy";
                url = "http://127.0.0.1:9090";
                uid = "prometheus";
                isDefault = true;
              }
            ];
          };
          dashboards.settings = {
            apiVersion = 1;
            providers = [
              {
                name = "homelab";
                type = "file";
                options.path = "/etc/grafana/dashboards";
              }
            ];
          };
        };
      };

      services.gatus = {
        enable = true;
        openFirewall = true;
        settings = {
          web.port = 8080;
          metrics = true;
          endpoints = map gatusEndpoint stack.serviceChecks;
        };
      };

      environment.etc."grafana/dashboards/homelab-overview.json".source = homelabDashboard;

      networking.firewall.allowedTCPPorts = [ 9090 ];
    })
  ];
}
