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

  # Scrape targets are derived from the topology rather than duplicated here,
  # so a host is registered in exactly one place. Hosts opt in with
  # `monitoring.enable = true`, which nixos-factory writes for every container
  # it creates; appliances and roaming machines simply omit it.
  defaultHosts = lib.attrNames (
    lib.filterAttrs (_: host: host.monitoring.enable or false) networkTopology.hosts
  );

  fqdn = host: "${host}.${lanDomain}";
  mkTarget = port: host: "${fqdn host}:${toString port}";

  # Keep legends readable: "immich-nix", not "immich-nix.lan:9100".
  shortInstance = [
    {
      source_labels = [ "__address__" ];
      regex = "([^.]+)\\..*";
      target_label = "instance";
      replacement = "$1";
    }
  ];

  defaultServiceChecks = [
    {
      name = "Authentik";
      url = "https://auth.tsawhill.org";
    }
    {
      name = "Vaultwarden";
      url = "https://vault.tsawhill.org";
    }
    {
      name = "Immich";
      url = "https://immich.tsawhill.org";
    }
    {
      name = "Jellyfin";
      url = "https://jelly.tsawhill.org";
    }
    {
      name = "Nextcloud";
      url = "https://nc.tsawhill.org";
    }
    {
      name = "Open WebUI";
      url = "https://llm.tsawhill.org";
    }
    {
      name = "Gotify";
      url = "https://gotify.tsawhill.org";
    }
    {
      name = "Radarr";
      url = "https://rad.tsawhill.org";
    }
    {
      name = "Sonarr";
      url = "https://son.tsawhill.org";
    }
    {
      name = "Lidarr";
      url = "https://lid.tsawhill.org";
    }
    {
      name = "Prowlarr";
      url = "https://pro.tsawhill.org";
    }
    {
      name = "Jellyseerr";
      url = "https://request.tsawhill.org";
    }
    {
      name = "Searx";
      url = "https://searx.tsawhill.org";
    }
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

  promDatasource = {
    type = "prometheus";
    uid = "prometheus";
  };

  mkThresholds = steps: {
    mode = "absolute";
    inherit steps;
  };

  mkStat =
    {
      id,
      title,
      expr,
      x,
      y,
      w ? 6,
      h ? 4,
      unit ? "none",
      steps ? [
        {
          color = "text";
          value = null;
        }
      ],
    }:
    {
      inherit id title;
      type = "stat";
      gridPos = {
        inherit
          h
          w
          x
          y
          ;
      };
      datasource = promDatasource;
      fieldConfig = {
        defaults = {
          inherit unit;
          color.mode = "thresholds";
          thresholds = mkThresholds steps;
        };
        overrides = [ ];
      };
      options = {
        colorMode = "value";
        graphMode = "area";
        justifyMode = "auto";
        orientation = "auto";
        textMode = "auto";
        reduceOptions = {
          calcs = [ "lastNotNull" ];
          fields = "";
          values = false;
        };
      };
      targets = [
        {
          refId = "A";
          datasource = promDatasource;
          inherit expr;
          instant = true;
        }
      ];
    };

  mkGraph =
    {
      id,
      title,
      expr,
      x,
      y,
      unit,
      w ? 12,
      h ? 8,
      legend ? "{{instance}}",
      min ? 0,
      max ? null,
      description ? "",
    }:
    {
      inherit id title description;
      type = "timeseries";
      gridPos = {
        inherit
          h
          w
          x
          y
          ;
      };
      datasource = promDatasource;
      fieldConfig = {
        defaults = {
          inherit unit min max;
          color.mode = "palette-classic";
          custom = {
            axisPlacement = "auto";
            drawStyle = "line";
            fillOpacity = 8;
            lineInterpolation = "smooth";
            lineWidth = 1;
            showPoints = "never";
            spanNulls = true;
          };
          thresholds = mkThresholds [
            {
              color = "green";
              value = null;
            }
          ];
        };
        overrides = [ ];
      };
      options = {
        legend = {
          calcs = [
            "lastNotNull"
            "max"
          ];
          displayMode = "table";
          placement = "right";
          showLegend = true;
        };
        tooltip = {
          mode = "multi";
          sort = "desc";
        };
      };
      targets = [
        {
          refId = "A";
          datasource = promDatasource;
          inherit expr;
          legendFormat = legend;
        }
      ];
    };

  homelabDashboard = pkgs.writeText "homelab-overview-dashboard.json" (
    builtins.toJSON {
      uid = "homelab-overview";
      title = "Homelab Overview";
      timezone = "browser";
      schemaVersion = 39;
      version = 1;
      editable = true;
      refresh = "30s";
      tags = [
        "homelab"
        "nixos"
      ];
      time = {
        from = "now-6h";
        to = "now";
      };
      annotations.list = [ ];
      links = [ ];
      templating.list = [
        {
          name = "host";
          label = "Host";
          type = "query";
          datasource = promDatasource;
          query = {
            qryType = 1;
            query = "label_values(node_uname_info, instance)";
            refId = "PrometheusVariableQueryEditor-VariableQuery";
          };
          refresh = 1;
          sort = 1;
          multi = true;
          includeAll = true;
          allValue = ".*";
          current = {
            selected = true;
            text = [ "All" ];
            value = [ "$__all" ];
          };
        }
      ];
      panels = [
        (mkStat {
          id = 1;
          title = "Hosts Up";
          x = 0;
          y = 0;
          expr = ''sum(up{job="node"})'';
          steps = [
            {
              color = "red";
              value = null;
            }
            {
              color = "green";
              value = 1;
            }
          ];
        })
        (mkStat {
          id = 2;
          title = "Hosts Down";
          x = 6;
          y = 0;
          expr = ''count(up{job="node"} == 0) or vector(0)'';
          steps = [
            {
              color = "green";
              value = null;
            }
            {
              color = "red";
              value = 1;
            }
          ];
        })
        (mkStat {
          id = 3;
          title = "Services Up";
          x = 12;
          y = 0;
          expr = "sum(gatus_results_endpoint_success)";
          steps = [
            {
              color = "red";
              value = null;
            }
            {
              color = "green";
              value = 1;
            }
          ];
        })
        (mkStat {
          id = 4;
          title = "Services Down";
          x = 18;
          y = 0;
          expr = "count(gatus_results_endpoint_success == 0) or vector(0)";
          steps = [
            {
              color = "green";
              value = null;
            }
            {
              color = "red";
              value = 1;
            }
          ];
        })
        (mkGraph {
          id = 10;
          title = "CPU Busy";
          x = 0;
          y = 4;
          unit = "percent";
          max = 100;
          expr = ''100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle",instance=~"$host"}[5m])) * 100)'';
        })
        (mkGraph {
          id = 11;
          title = "Memory Used";
          x = 12;
          y = 4;
          unit = "percent";
          max = 100;
          expr = ''100 * (1 - (node_memory_MemAvailable_bytes{instance=~"$host"} / node_memory_MemTotal_bytes{instance=~"$host"}))'';
        })
        (mkGraph {
          id = 12;
          title = "Root Disk Used";
          x = 0;
          y = 12;
          unit = "percent";
          max = 100;
          expr = ''100 * (1 - (node_filesystem_avail_bytes{instance=~"$host",mountpoint="/",fstype!~"tmpfs|overlay|ramfs"} / node_filesystem_size_bytes{instance=~"$host",mountpoint="/",fstype!~"tmpfs|overlay|ramfs"}))'';
        })
        (mkGraph {
          id = 13;
          title = "Load (1m, per core)";
          description = "Load average normalised by core count; sustained values above 1 mean the host is saturated.";
          x = 12;
          y = 12;
          unit = "none";
          max = null;
          expr = ''node_load1{instance=~"$host"} / on(instance) group_left count by (instance) (node_cpu_seconds_total{mode="idle",instance=~"$host"})'';
        })
        (mkGraph {
          id = 14;
          title = "Network Received";
          x = 0;
          y = 20;
          unit = "Bps";
          max = null;
          expr = ''sum by (instance) (rate(node_network_receive_bytes_total{instance=~"$host",device!~"lo|veth.*|docker.*|br-.*"}[5m]))'';
        })
        (mkGraph {
          id = 15;
          title = "Network Transmitted";
          x = 12;
          y = 20;
          unit = "Bps";
          max = null;
          expr = ''sum by (instance) (rate(node_network_transmit_bytes_total{instance=~"$host",device!~"lo|veth.*|docker.*|br-.*"}[5m]))'';
        })
        (mkGraph {
          id = 16;
          title = "Disk Read";
          x = 0;
          y = 28;
          unit = "Bps";
          max = null;
          expr = ''sum by (instance) (rate(node_disk_read_bytes_total{instance=~"$host"}[5m]))'';
        })
        (mkGraph {
          id = 17;
          title = "Disk Written";
          x = 12;
          y = 28;
          unit = "Bps";
          max = null;
          expr = ''sum by (instance) (rate(node_disk_written_bytes_total{instance=~"$host"}[5m]))'';
        })
        {
          id = 20;
          title = "Service Health";
          description = "Gatus endpoint checks over the selected window.";
          type = "state-timeline";
          gridPos = {
            h = 10;
            w = 24;
            x = 0;
            y = 36;
          };
          datasource = promDatasource;
          fieldConfig = {
            defaults = {
              color.mode = "thresholds";
              custom = {
                fillOpacity = 80;
                lineWidth = 0;
              };
              mappings = [
                {
                  type = "value";
                  options = {
                    "0" = {
                      text = "Down";
                      color = "red";
                      index = 0;
                    };
                    "1" = {
                      text = "Up";
                      color = "green";
                      index = 1;
                    };
                  };
                }
              ];
              thresholds = mkThresholds [
                {
                  color = "red";
                  value = null;
                }
              ];
            };
            overrides = [ ];
          };
          options = {
            alignValue = "center";
            mergeValues = true;
            rowHeight = 0.9;
            showValue = "never";
            legend = {
              displayMode = "list";
              placement = "bottom";
              showLegend = false;
            };
            tooltip.mode = "single";
          };
          targets = [
            {
              refId = "A";
              datasource = promDatasource;
              expr = "gatus_results_endpoint_success";
              legendFormat = "{{name}}";
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
            relabel_configs = shortInstance;
          }
          {
            job_name = "systemd";
            static_configs = [
              { targets = map (mkTarget 9558) stack.monitoredHosts; }
            ];
            relabel_configs = shortInstance;
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
        settings = {
          security = {
            secret_key = "$__file{${config.sops.secrets.grafana_secret_key.path}}";
            admin_password = "$__file{${config.sops.secrets.grafana_admin_password.path}}";
          };
          server = {
            http_addr = "0.0.0.0";
            http_port = 3000;
            domain = "monitoring-nix.${lanDomain}";
          };
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
