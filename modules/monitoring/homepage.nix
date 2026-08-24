{
  config,
  lib,
  networkTopology,
  ...
}:

let
  cfg = config.my.monitoring.homepage;
  lanDomain = networkTopology.domains.lan;
  prometheus = "http://${cfg.prometheusHost}.${lanDomain}:9090";

  intermittentHosts = lib.attrNames (
    lib.filterAttrs (_: host: host.incus.intermittent or false) networkTopology.hosts
  );
  intermittentHostRegex =
    if intermittentHosts == [ ] then
      "a^"
    else
      "^(${lib.concatMapStringsSep "|" lib.escapeRegex intermittentHosts})$";
  zfsPoolRegex = "^(zpool|downloadHDD|downloadSSD|rpool)$";

  # One catalogue drives both the uptime checks and the bookmark tiles, so a
  # new service only has to be added once.
  defaultServices = [
    {
      name = "Jellyfin";
      url = "https://jelly.tsawhill.org";
      icon = "si:jellyfin";
      group = "Media";
    }
    {
      name = "Jellyseerr";
      url = "https://request.tsawhill.org";
      icon = "sh:jellyseerr";
      group = "Media";
    }
    {
      name = "Immich";
      url = "https://immich.tsawhill.org";
      icon = "si:immich";
      group = "Media";
    }
    {
      name = "Sonarr";
      url = "https://son.tsawhill.org";
      icon = "si:sonarr";
      group = "Arrs";
      altStatus = [
        401
        403
      ];
    }
    {
      name = "Radarr";
      url = "https://rad.tsawhill.org";
      icon = "si:radarr";
      group = "Arrs";
      altStatus = [
        401
        403
      ];
    }
    {
      name = "Lidarr";
      url = "https://lid.tsawhill.org";
      icon = "sh:lidarr";
      group = "Arrs";
      altStatus = [
        401
        403
      ];
    }
    {
      name = "Prowlarr";
      url = "https://pro.tsawhill.org";
      icon = "sh:prowlarr";
      group = "Arrs";
      altStatus = [
        401
        403
      ];
    }
    {
      name = "Nextcloud";
      url = "https://nc.tsawhill.org";
      icon = "si:nextcloud";
      group = "Infra";
    }
    {
      name = "Vaultwarden";
      url = "https://vault.tsawhill.org";
      icon = "sh:vaultwarden";
      group = "Infra";
    }
    {
      name = "Authentik";
      url = "https://auth.tsawhill.org";
      icon = "sh:authentik";
      group = "Infra";
    }
    {
      name = "Gotify";
      url = "https://gotify.tsawhill.org";
      icon = "sh:gotify";
      group = "Infra";
    }
    {
      name = "Open WebUI";
      url = "https://llm.tsawhill.org";
      icon = "sh:open-webui";
      group = "Tools";
    }
    {
      name = "Searx";
      url = "https://searx.tsawhill.org";
      icon = "si:searxng";
      group = "Tools";
    }
  ];

  # Launcher links only: either LAN-only admin pages, or hosts that are
  # usually powered off, where a health check would just show red.
  defaultInternalLinks = [
    {
      name = "Unifi";
      url = "https://unifi.tsawhill.org";
      icon = "si:ubiquiti";
      group = "Infra";
    }
    {
      name = "Grafana";
      url = "https://grafana.tsawhill.org";
      icon = "si:grafana";
      group = "Monitoring";
    }
    {
      name = "Prometheus";
      url = "https://prom.tsawhill.org";
      icon = "si:prometheus";
      group = "Monitoring";
    }
    {
      name = "Gatus";
      url = "https://status.tsawhill.org";
      icon = "sh:gatus";
      group = "Monitoring";
    }
    {
      name = "AdGuard";
      url = "http://adguard-nix.${lanDomain}:3000";
      icon = "sh:adguard-home";
      group = "Monitoring";
    }
    {
      name = "YouTube";
      url = "https://youtube.com";
      icon = "si:youtube";
      group = "Daily";
    }
    {
      name = "Reddit";
      url = "https://reddit.com";
      icon = "si:reddit";
      group = "Daily";
    }
    {
      name = "Twitter";
      url = "https://x.com";
      icon = "si:x";
      group = "Daily";
    }
    {
      name = "Twitch";
      url = "https://twitch.tv";
      icon = "si:twitch";
      group = "Daily";
    }
    {
      name = "Amazon";
      url = "https://amazon.com";
      icon = "si:amazon";
      group = "Daily";
    }
    {
      name = "Claude";
      url = "https://claude.ai";
      icon = "si:anthropic";
      group = "Daily";
    }
    {
      name = "ChatGPT";
      url = "https://chatgpt.com";
      icon = "si:openai";
      group = "Daily";
    }
  ];

  allLinks = cfg.services ++ cfg.internalLinks;

  presentGroups = lib.unique (map (s: s.group) allLinks);

  # Listed groups come first in the order given; anything unlisted keeps its
  # definition order and lands at the bottom.
  groupsInOrder =
    lib.filter (g: lib.elem g presentGroups) cfg.groupOrder
    ++ lib.filter (g: !lib.elem g cfg.groupOrder) presentGroups;

  mkBookmarkGroup = group: {
    title = group;
    links = map (s: {
      title = s.name;
      url = s.url;
      icon = s.icon or "";
    }) (lib.filter (s: s.group == group) allLinks);
  };

  mkMonitorSite =
    s:
    {
      title = s.name;
      url = s.url;
      icon = s.icon or "";
    }
    // lib.optionalAttrs (s ? altStatus) { alt-status-codes = s.altStatus; };

  asMeasurement = measurement: expression: ''
    label_replace((${expression}), "measurement", "${measurement}", "", "")
  '';

  multiMeasurementQuery = measurements: lib.concatStringsSep " or " measurements;

  cpuBusy = ''100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)'';
  topCpuBusy = "topk(5, ${cpuBusy})";
  memoryUsed = "node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes";
  memoryPercent = "100 * (${memoryUsed}) / node_memory_MemTotal_bytes";
  topMemoryPercent = "topk(5, ${memoryPercent})";
  rootFilesystemFilter = ''mountpoint="/",fstype!~"tmpfs|overlay|ramfs"'';
  rootUsed = "node_filesystem_size_bytes{${rootFilesystemFilter}} - node_filesystem_avail_bytes{${rootFilesystemFilter}}";
  rootPercent = "100 * (${rootUsed}) / node_filesystem_size_bytes{${rootFilesystemFilter}}";
  topRootPercent = "topk(5, ${rootPercent})";

  cpuQuery = multiMeasurementQuery [
    (asMeasurement "percent" topCpuBusy)
    (asMeasurement "total" ''
      count by (instance) (node_cpu_seconds_total{mode="idle"})
        and on (instance) ${topCpuBusy}
    '')
  ];

  memoryQuery = multiMeasurementQuery [
    (asMeasurement "percent" topMemoryPercent)
    (asMeasurement "used" "(${memoryUsed}) / 1073741824 and on (instance) ${topMemoryPercent}")
    (asMeasurement "total" "node_memory_MemTotal_bytes / 1073741824 and on (instance) ${topMemoryPercent}")
  ];

  rootDiskQuery = multiMeasurementQuery [
    (asMeasurement "percent" topRootPercent)
    (asMeasurement "used" "(${rootUsed}) / 1073741824 and on (instance) ${topRootPercent}")
    (asMeasurement "total" "node_filesystem_size_bytes{${rootFilesystemFilter}} / 1073741824 and on (instance) ${topRootPercent}")
  ];

  zfsPercent = ''
    100 * zfs_pool_allocated_bytes{instance="server-nix",pool=~"${zfsPoolRegex}"}
      / zfs_pool_size_bytes{instance="server-nix",pool=~"${zfsPoolRegex}"}
  '';
  zfsQuery = multiMeasurementQuery [
    (asMeasurement "percent" zfsPercent)
    (asMeasurement "used" ''zfs_pool_allocated_bytes{instance="server-nix",pool=~"${zfsPoolRegex}"} / 1099511627776'')
    (asMeasurement "total" ''zfs_pool_size_bytes{instance="server-nix",pool=~"${zfsPoolRegex}"} / 1099511627776'')
    (asMeasurement "online" ''
      label_replace(
        node_zfs_zpool_state{instance="server-nix",state="online",zpool=~"${zfsPoolRegex}"},
        "pool", "$1", "zpool", "(.*)"
      )
    '')
  ];

  fleetQuery = multiMeasurementQuery [
    (asMeasurement "up" ''sum(up{job="node",instance!~"${intermittentHostRegex}"}) or vector(0)'')
    (asMeasurement "total" ''count(up{job="node",instance!~"${intermittentHostRegex}"}) or vector(0)'')
  ];

  # Prometheus returns value[1] as a numeric string; gjson coerces it for us.
  cpuWidget = {
    type = "custom-api";
    title = "CPU Busy";
    cache = "1m";
    url = "${prometheus}/api/v1/query";
    parameters.query = cpuQuery;
    template = ''
      {{ $results := .JSON.Array "data.result" }}
      {{ if eq (len $results) 0 }}
        <p class="color-subdue">no data</p>
      {{ else }}
        <ul class="list list-gap-10">
          {{ range $results }}
            {{ if eq (.String "metric.measurement") "percent" }}
              {{ $instance := .String "metric.instance" }}
              {{ $pct := .Float "value.1" }}
              <li>
                <div class="flex justify-between">
                  <span class="color-highlight text-truncate">{{ $instance }}</span>
                  <span class="size-h5">
                    {{- printf "%.0f%% of " $pct -}}
                    {{- range $results -}}
                      {{- if and (eq (.String "metric.instance") $instance) (eq (.String "metric.measurement") "total") -}}
                        {{- printf "%.0f logical CPUs" (.Float "value.1") -}}
                      {{- end -}}
                    {{- end -}}
                  </span>
                </div>
                <div style="height:3px;background:var(--color-separator);margin-top:4px;">
                  <div style="height:3px;width:{{ printf "%.0f" $pct }}%;background:var(--color-primary);"></div>
                </div>
              </li>
            {{ end }}
          {{ end }}
        </ul>
      {{ end }}
    '';
  };

  capacityWidget =
    {
      title,
      query,
      nameLabel ? "instance",
      unit ? "GiB",
      showHealth ? false,
    }:
    {
      type = "custom-api";
      inherit title;
      cache = "1m";
      url = "${prometheus}/api/v1/query";
      parameters.query = query;
      template = ''
        {{ $results := .JSON.Array "data.result" }}
        {{ if eq (len $results) 0 }}
          <p class="color-subdue">no data</p>
        {{ else }}
          <ul class="list list-gap-10">
            {{ range $results }}
              {{ if eq (.String "metric.measurement") "percent" }}
                {{ $name := .String "metric.${nameLabel}" }}
                {{ $pct := .Float "value.1" }}
                <li>
                  <div class="flex justify-between">
                    <span class="color-highlight text-truncate">{{ $name }}</span>
                    ${lib.optionalString showHealth ''
                      {{ range $results }}
                        {{ if and (eq (.String "metric.${nameLabel}") $name) (eq (.String "metric.measurement") "online") }}
                          {{ if eq (.String "value.1") "1" }}
                            <span class="size-h6 color-positive">ONLINE</span>
                          {{ else }}
                            <span class="size-h6 color-negative">NOT ONLINE</span>
                          {{ end }}
                        {{ end }}
                      {{ end }}
                    ''}
                  </div>
                  <div class="flex justify-end size-h5">
                    <span>
                      {{- range $results -}}
                        {{- if and (eq (.String "metric.${nameLabel}") $name) (eq (.String "metric.measurement") "used") -}}
                          {{- printf "%.1f/" (.Float "value.1") -}}
                        {{- end -}}
                      {{- end -}}
                      {{- range $results -}}
                        {{- if and (eq (.String "metric.${nameLabel}") $name) (eq (.String "metric.measurement") "total") -}}
                          {{- printf "%.1f" (.Float "value.1") -}}
                        {{- end -}}
                      {{- end -}}
                      ${unit} ({{ printf "%.0f%%" $pct }})
                    </span>
                  </div>
                  <div style="height:3px;background:var(--color-separator);margin-top:4px;">
                    <div style="height:3px;width:{{ printf "%.0f" $pct }}%;background:var(--color-primary);"></div>
                  </div>
                </li>
              {{ end }}
            {{ end }}
          </ul>
        {{ end }}
      '';
    };

  alertsQuery = lib.concatStringsSep " or " [
    ''label_replace(100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > ${toString cfg.thresholds.cpu}, "alert", "cpu", "", "")''
    ''label_replace(100 * (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) > ${toString cfg.thresholds.memory}, "alert", "memory", "", "")''
    ''label_replace(100 * (1 - node_filesystem_avail_bytes{mountpoint="/",fstype!~"tmpfs|overlay|ramfs"} / node_filesystem_size_bytes{mountpoint="/",fstype!~"tmpfs|overlay|ramfs"}) > ${toString cfg.thresholds.disk}, "alert", "disk", "", "")''
    ''label_replace(up{job="node",instance!~"${intermittentHostRegex}"} == 0, "alert", "down", "", "")''
    ''label_replace(node_zfs_zpool_state{instance="server-nix",state!="online",zpool=~"${zfsPoolRegex}"} == 1, "alert", "zpool", "", "")''
    ''label_replace(vpn_egress_tunnel_up{instance="networking-vpn-out-na1-nix"} == 0, "alert", "vpn", "", "")''
    ''label_replace(searx_vpn_backoff_active{instance="searx-nix"} == 1, "alert", "searx-vpn", "", "")''
  ];
in
{
  options.my.monitoring.homepage = {
    enable = lib.mkEnableOption "Glance homelab homepage";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Port Glance listens on.";
    };

    prometheusHost = lib.mkOption {
      type = lib.types.str;
      default = "monitoring-nix";
      description = "Host running Prometheus, used for the usage and alert widgets.";
    };

    services = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      default = defaultServices;
      description = "Externally reachable services to monitor and link.";
    };

    groupOrder = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "Daily"
        "Media"
        "Arrs"
        "Infra"
        "Tools"
        "Monitoring"
      ];
      description = "Order bookmark groups are rendered in; unlisted groups are appended.";
    };

    internalLinks = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      default = defaultInternalLinks;
      description = "Pages to link but not health-check: LAN-only admin UIs, hosts that are usually off, and everyday external sites.";
    };

    thresholds = {
      cpu = lib.mkOption {
        type = lib.types.int;
        default = 80;
        description = "CPU busy percent above which a host is flagged.";
      };
      memory = lib.mkOption {
        type = lib.types.int;
        default = 85;
        description = "Memory used percent above which a host is flagged.";
      };
      disk = lib.mkOption {
        type = lib.types.int;
        default = 85;
        description = "Root disk used percent above which a host is flagged.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.glance = {
      enable = true;
      openFirewall = true;
      settings = {
        server = {
          host = "0.0.0.0";
          inherit (cfg) port;
        };

        theme = {
          background-color = "225 14 12";
          primary-color = "195 60 65";
          negative-color = "358 65 60";
          contrast-multiplier = 1.1;
        };

        pages = [
          {
            name = "Home";
            head-widgets = [
              {
                type = "search";
                search-engine = "https://searx.tsawhill.org/search?q={QUERY}";
                new-tab = false;
                bangs = [
                  {
                    title = "Google";
                    shortcut = "!g";
                    url = "https://www.google.com/search?q={QUERY}";
                  }
                  {
                    title = "DuckDuckGo";
                    shortcut = "!ddg";
                    url = "https://duckduckgo.com/?q={QUERY}";
                  }
                ];
              }
            ];
            columns = [
              {
                size = "small";
                widgets = [
                  {
                    type = "bookmarks";
                    groups = map mkBookmarkGroup groupsInOrder;
                  }
                ];
              }
              {
                size = "full";
                widgets = [
                  {
                    type = "custom-api";
                    title = "Needs Attention";
                    css-class = "needs-attention-widget";
                    cache = "1m";
                    url = "${prometheus}/api/v1/query";
                    parameters.query = alertsQuery;
                    template = ''
                      {{ $results := .JSON.Array "data.result" }}
                      {{ if eq (len $results) 0 }}
                        <style>.needs-attention-widget { display: none; }</style>
                      {{ else }}
                        <ul class="list list-gap-10">
                          {{ range $results }}
                            {{ $kind := .String "metric.alert" }}
                            <li class="flex justify-between">
                              <span class="color-negative text-truncate">{{ .String "metric.instance" }}</span>
                              <span class="size-h6 color-subdue">
                                {{ if eq $kind "down" }}
                                  exporter down
                                {{ else if eq $kind "zpool" }}
                                  {{ .String "metric.zpool" }} {{ .String "metric.state" }}
                                {{ else if eq $kind "vpn" }}
                                  VPN tunnel unhealthy (leak prevention active)
                                {{ else if eq $kind "searx-vpn" }}
                                  Startpage remediation backed off
                                {{ else }}
                                  {{ $kind }} {{ printf "%.0f%%" (.Float "value.1") }}
                                {{ end }}
                              </span>
                            </li>
                          {{ end }}
                        </ul>
                      {{ end }}
                    '';
                  }
                  {
                    type = "monitor";
                    title = "Services";
                    cache = "2m";
                    sites = map mkMonitorSite cfg.services;
                  }
                  cpuWidget
                  (capacityWidget {
                    title = "Memory Used";
                    query = memoryQuery;
                  })
                ];
              }
              {
                size = "small";
                widgets = [
                  {
                    type = "clock";
                    hour-format = "12h";
                  }
                  {
                    type = "custom-api";
                    title = "Fleet";
                    cache = "1m";
                    url = "${prometheus}/api/v1/query";
                    parameters.query = fleetQuery;
                    template = ''
                      {{ $results := .JSON.Array "data.result" }}
                      <div class="flex justify-between">
                        <span class="color-subdue">Hosts up</span>
                        <span class="size-h3 color-highlight">
                          {{- range $results -}}
                            {{- if eq (.String "metric.measurement") "up" -}}
                              {{- printf "%.0f/" (.Float "value.1") -}}
                            {{- end -}}
                          {{- end -}}
                          {{- range $results -}}
                            {{- if eq (.String "metric.measurement") "total" -}}
                              {{- printf "%.0f" (.Float "value.1") -}}
                            {{- end -}}
                          {{- end -}}
                        </span>
                      </div>
                    '';
                  }
                  (capacityWidget {
                    title = "Root Disk Used";
                    query = rootDiskQuery;
                  })
                  (capacityWidget {
                    title = "Server ZFS Pools";
                    query = zfsQuery;
                    nameLabel = "pool";
                    unit = "TiB";
                    showHealth = true;
                  })
                ];
              }
            ];
          }
        ];
      };
    };
  };
}
