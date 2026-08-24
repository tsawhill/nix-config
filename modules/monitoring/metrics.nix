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
  monitoredTopologyHosts = lib.filterAttrs (
    _: host: host.monitoring.enable or false
  ) networkTopology.hosts;
  defaultHosts = lib.attrNames monitoredTopologyHosts;
  incusHosts = lib.attrNames (lib.filterAttrs (_: host: host ? incus) monitoredTopologyHosts);
  independentHosts = lib.attrNames (
    lib.filterAttrs (_: host: !(host ? incus)) monitoredTopologyHosts
  );
  intermittentHosts = lib.attrNames (
    lib.filterAttrs (_: host: host.incus.intermittent or false) monitoredTopologyHosts
  );
  mkHostRegex =
    hosts: if hosts == [ ] then "a^" else "^(${lib.concatMapStringsSep "|" lib.escapeRegex hosts})$";
  incusHostRegex = mkHostRegex incusHosts;
  independentHostRegex = mkHostRegex independentHosts;
  intermittentHostRegex = mkHostRegex intermittentHosts;
  independentNetworkDeviceRegex = mkHostRegex (
    lib.unique (
      lib.concatMap (
        host: networkTopology.hosts.${host}.monitoring.networkDevices or [ ]
      ) independentHosts
    )
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

  nodeSelector = ''instance=~"$host",instance=~"${independentHostRegex}"'';
  incusSelector = ''project="default",type="container",name=~"$host",name=~"${incusHostRegex}"'';

  normaliseIncus = expression: ''
    max by (instance) (
      label_replace((${expression}), "instance", "$1", "name", "(.*)")
    )
  '';
  combineHostMetrics = nodeExpression: incusExpression: ''
    (${nodeExpression}) or (${normaliseIncus incusExpression})
  '';

  nodeCpuCores = ''count by (instance) (node_cpu_seconds_total{mode="idle",${nodeSelector}})'';
  nodeCpuBusyFraction = ''1 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle",${nodeSelector}}[5m]))'';
  incusCpuCores = "max by (name) (incus_cpu_effective_total{${incusSelector}})";
  incusCpuUsedCores = ''sum by (name) (rate(incus_cpu_seconds_total{${incusSelector},mode=~"user|system"}[5m]))'';
  cpuPercentExpr = combineHostMetrics "100 * (${nodeCpuBusyFraction})" "100 * (${incusCpuUsedCores}) / (${incusCpuCores})";
  cpuUsedCoresExpr = combineHostMetrics "(${nodeCpuBusyFraction}) * on (instance) (${nodeCpuCores})" incusCpuUsedCores;
  cpuAllocatedExpr = combineHostMetrics nodeCpuCores incusCpuCores;

  nodeMemoryUsed = "node_memory_MemTotal_bytes{${nodeSelector}} - node_memory_MemAvailable_bytes{${nodeSelector}}";
  nodeMemoryTotal = "node_memory_MemTotal_bytes{${nodeSelector}}";
  incusMemoryUsed = "max by (name) (incus_memory_MemTotal_bytes{${incusSelector}} - incus_memory_MemAvailable_bytes{${incusSelector}})";
  incusMemoryTotal = "max by (name) (incus_memory_MemTotal_bytes{${incusSelector}})";
  memoryPercentExpr = combineHostMetrics "100 * (${nodeMemoryUsed}) / (${nodeMemoryTotal})" "100 * (${incusMemoryUsed}) / (${incusMemoryTotal})";
  memoryUsedExpr = combineHostMetrics nodeMemoryUsed incusMemoryUsed;
  memoryAllocatedExpr = combineHostMetrics nodeMemoryTotal incusMemoryTotal;

  networkExpr =
    direction:
    combineHostMetrics ''sum by (instance) (rate(node_network_${direction}_bytes_total{${nodeSelector},device=~"${independentNetworkDeviceRegex}"}[$__rate_interval]))'' ''sum by (name) (rate(incus_network_${direction}_bytes_total{${incusSelector},device="eth0"}[$__rate_interval]))'';

  diskExpr =
    direction:
    combineHostMetrics ''sum by (instance) (rate(node_disk_${direction}_bytes_total{${nodeSelector},device=~"sd[a-z]+|nvme[0-9]+n[0-9]+"}[5m]))'' "sum by (name) (rate(incus_disk_${direction}_bytes_total{${incusSelector}}[5m]))";

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
    # / returns 404, which the default conditions would accept as healthy.
    {
      name = "Firefox Sync";
      url = "https://ffsync.tsawhill.org/__heartbeat__";
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

  resourceTable = {
    id = 18;
    title = "Current CPU & Memory";
    description = "Current usage and the CPU/RAM allocated to each host or Incus guest.";
    type = "table";
    gridPos = {
      h = 8;
      w = 24;
      x = 0;
      y = 12;
    };
    datasource = promDatasource;
    fieldConfig = {
      defaults = {
        custom = {
          align = "auto";
          cellOptions.type = "auto";
          inspect = false;
        };
      };
      overrides = [
        {
          matcher = {
            id = "byName";
            options = "CPU %";
          };
          properties = [
            {
              id = "unit";
              value = "percent";
            }
            {
              id = "decimals";
              value = 1;
            }
          ];
        }
        {
          matcher = {
            id = "byName";
            options = "CPU used (cores)";
          };
          properties = [
            {
              id = "unit";
              value = "none";
            }
            {
              id = "decimals";
              value = 2;
            }
          ];
        }
        {
          matcher = {
            id = "byName";
            options = "CPU allocated (cores)";
          };
          properties = [
            {
              id = "unit";
              value = "none";
            }
            {
              id = "decimals";
              value = 0;
            }
          ];
        }
        {
          matcher = {
            id = "byRegexp";
            options = "/^RAM (used|allocated)$/";
          };
          properties = [
            {
              id = "unit";
              value = "bytes";
            }
            {
              id = "decimals";
              value = 2;
            }
          ];
        }
        {
          matcher = {
            id = "byName";
            options = "RAM %";
          };
          properties = [
            {
              id = "unit";
              value = "percent";
            }
            {
              id = "decimals";
              value = 1;
            }
          ];
        }
      ];
    };
    options = {
      cellHeight = "sm";
      showHeader = true;
      footer.show = false;
    };
    transformations = [
      {
        id = "joinByField";
        options = {
          byField = "instance";
          mode = "outer";
        };
      }
      {
        id = "organize";
        options = {
          excludeByName = {
            Time = true;
            "Time 1" = true;
            "Time 2" = true;
            "Time 3" = true;
            "Time 4" = true;
            "Time 5" = true;
          };
          indexByName = {
            instance = 0;
            "Value #A" = 1;
            "Value #B" = 2;
            "Value #C" = 3;
            "Value #D" = 4;
            "Value #E" = 5;
            "Value #F" = 6;
          };
          renameByName = {
            instance = "Host";
            "Value #A" = "CPU %";
            "Value #B" = "CPU used (cores)";
            "Value #C" = "CPU allocated (cores)";
            "Value #D" = "RAM %";
            "Value #E" = "RAM used";
            "Value #F" = "RAM allocated";
          };
        };
      }
    ];
    targets =
      lib.imap0
        (index: target: {
          refId = builtins.elemAt [
            "A"
            "B"
            "C"
            "D"
            "E"
            "F"
          ] index;
          datasource = promDatasource;
          expr = target;
          format = "table";
          instant = true;
          range = false;
        })
        [
          cpuPercentExpr
          cpuUsedCoresExpr
          cpuAllocatedExpr
          memoryPercentExpr
          memoryUsedExpr
          memoryAllocatedExpr
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
          expr = ''sum(up{job="node",instance!~"${intermittentHostRegex}"})'';
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
          expr = ''count(up{job="node",instance!~"${intermittentHostRegex}"} == 0) or vector(0)'';
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
          description = "Percentage of each host's allocated logical CPUs currently in use; exact used/allocated values are listed below.";
          x = 0;
          y = 4;
          unit = "percent";
          max = 100;
          expr = cpuPercentExpr;
        })
        (mkGraph {
          id = 11;
          title = "Memory Used";
          description = "Percentage of each host's allocated memory currently in use; exact used/allocated values are listed below.";
          x = 12;
          y = 4;
          unit = "percent";
          max = 100;
          expr = memoryPercentExpr;
        })
        resourceTable
        (mkGraph {
          id = 12;
          title = "Root Disk Used";
          x = 0;
          y = 20;
          unit = "percent";
          max = 100;
          expr = ''100 * (1 - (node_filesystem_avail_bytes{instance=~"$host",mountpoint="/",fstype!~"tmpfs|overlay|ramfs"} / node_filesystem_size_bytes{instance=~"$host",mountpoint="/",fstype!~"tmpfs|overlay|ramfs"}))'';
        })
        (mkGraph {
          id = 13;
          title = "CPU Used (logical cores)";
          description = "Average logical CPU capacity in use; compare with the allocated totals in the table above.";
          x = 12;
          y = 20;
          unit = "none";
          max = null;
          expr = cpuUsedCoresExpr;
        })
        (mkGraph {
          id = 14;
          title = "Network Received";
          description = "Incus per-instance eth0 traffic for guests; br0 management traffic for server-nix. Bridge, tap, veth, loopback, and nested-container interfaces are not double-counted.";
          x = 0;
          y = 28;
          unit = "Bps";
          max = null;
          expr = networkExpr "receive";
        })
        (mkGraph {
          id = 15;
          title = "Network Transmitted";
          description = "Incus per-instance eth0 traffic for guests; br0 management traffic for server-nix. Bridge, tap, veth, loopback, and nested-container interfaces are not double-counted.";
          x = 12;
          y = 28;
          unit = "Bps";
          max = null;
          expr = networkExpr "transmit";
        })
        (mkGraph {
          id = 16;
          title = "Disk Read";
          description = "Incus cgroup-attributed physical I/O for guests plus physical-device I/O for independent hosts.";
          x = 0;
          y = 36;
          unit = "Bps";
          max = null;
          expr = diskExpr "read";
        })
        (mkGraph {
          id = 17;
          title = "Disk Written";
          description = "Incus cgroup-attributed physical I/O for guests plus physical-device I/O for independent hosts.";
          x = 12;
          y = 36;
          unit = "Bps";
          max = null;
          expr = diskExpr "written";
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
            y = 44;
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
        (mkStat {
          id = 21;
          title = "VPN Tunnel";
          x = 0;
          y = 54;
          w = 6;
          expr = ''vpn_egress_tunnel_up{instance="networking-vpn-out-na1-nix"}'';
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
          id = 22;
          title = "VPN Handshake Age";
          x = 6;
          y = 54;
          w = 6;
          unit = "s";
          expr = ''vpn_egress_handshake_age_seconds{instance="networking-vpn-out-na1-nix"}'';
          steps = [
            {
              color = "green";
              value = null;
            }
            {
              color = "red";
              value = 180;
            }
          ];
        })
        (mkStat {
          id = 23;
          title = "Blocked VPN Exits";
          x = 12;
          y = 54;
          w = 6;
          expr = ''vpn_egress_blocked_exit_ips{instance="networking-vpn-out-na1-nix"}'';
          steps = [
            {
              color = "green";
              value = null;
            }
            {
              color = "yellow";
              value = 1;
            }
          ];
        })
        (mkStat {
          id = 24;
          title = "VPN Rotations (24h)";
          x = 18;
          y = 54;
          w = 6;
          expr = ''sum(increase(vpn_egress_rotations_total{instance="networking-vpn-out-na1-nix"}[24h])) or vector(0)'';
        })
        {
          id = 25;
          title = "Current VPN Exit";
          description = "The verified AirVPN endpoint and public exit address currently serving VPN clients.";
          type = "table";
          gridPos = {
            h = 4;
            w = 24;
            x = 0;
            y = 58;
          };
          datasource = promDatasource;
          fieldConfig.defaults.custom = {
            align = "auto";
            cellOptions.type = "auto";
            inspect = false;
          };
          options.showHeader = true;
          targets = [
            {
              refId = "A";
              datasource = promDatasource;
              expr = ''vpn_egress_info{instance="networking-vpn-out-na1-nix"}'';
              format = "table";
              instant = true;
              range = false;
            }
          ];
          transformations = [
            {
              id = "organize";
              options = {
                excludeByName = {
                  Time = true;
                  Value = true;
                  __name__ = true;
                  job = true;
                };
                renameByName = {
                  endpoint = "Endpoint";
                  instance = "Host";
                  public_ip = "Public IP";
                };
              };
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

      zfs = {
        enable = lib.mkEnableOption "Prometheus ZFS pool exporter";

        pools = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "ZFS pools whose capacity metrics should be exported.";
        };
      };
    };

    stack = {
      enable = lib.mkEnableOption "central Grafana, Prometheus, and Gatus monitoring";

      monitoredHosts = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = defaultHosts;
        description = "Hostnames to scrape for node and systemd exporter metrics.";
      };

      zfsHosts = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Hostnames to scrape for ZFS pool capacity metrics.";
      };

      serviceChecks = lib.mkOption {
        type = lib.types.listOf lib.types.attrs;
        default = defaultServiceChecks;
        description = "Gatus endpoint checks for service status.";
      };

      grafanaDomain = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "grafana.tsawhill.org";
        description = "Domain Grafana is reverse-proxied on; also sets root_url so generated links point at the proxy.";
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

    (lib.mkIf cfg.exporters.zfs.enable {
      services.prometheus.exporters.zfs = {
        enable = true;
        openFirewall = cfg.exporters.openFirewall;
        inherit (cfg.exporters.zfs) pools;
        extraFlags = [
          "--no-collector.dataset-filesystem"
          "--no-collector.dataset-volume"
          "--properties.pool=allocated,size"
        ];
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
        ]
        ++ lib.optional (stack.zfsHosts != [ ]) {
          job_name = "zfs";
          static_configs = [
            { targets = map (mkTarget 9134) stack.zfsHosts; }
          ];
          relabel_configs = shortInstance;
        };
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
            domain = if stack.grafanaDomain != null then stack.grafanaDomain else "monitoring-nix.${lanDomain}";
          }
          // lib.optionalAttrs (stack.grafanaDomain != null) {
            root_url = "https://${stack.grafanaDomain}/";
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
