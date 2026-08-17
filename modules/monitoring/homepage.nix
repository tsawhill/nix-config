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
      icon = "si:jellyfin";
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
      icon = "si:lidarr";
      group = "Arrs";
      altStatus = [
        401
        403
      ];
    }
    {
      name = "Prowlarr";
      url = "https://pro.tsawhill.org";
      icon = "si:prowlarr";
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
      icon = "si:bitwarden";
      group = "Infra";
    }
    {
      name = "Authentik";
      url = "https://auth.tsawhill.org";
      icon = "si:auth0";
      group = "Infra";
    }
    {
      name = "Gotify";
      url = "https://gotify.tsawhill.org";
      icon = "si:gotify";
      group = "Infra";
    }
    {
      name = "Open WebUI";
      url = "https://llm.tsawhill.org";
      icon = "si:ollama";
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
      url = "http://monitoring-nix.${lanDomain}:3000";
      icon = "si:grafana";
      group = "Monitoring";
    }
    {
      name = "Prometheus";
      url = "${prometheus}";
      icon = "si:prometheus";
      group = "Monitoring";
    }
    {
      name = "Gatus";
      url = "http://monitoring-nix.${lanDomain}:8080";
      icon = "si:statuspage";
      group = "Monitoring";
    }
    {
      name = "AdGuard";
      url = "http://adguard-nix.${lanDomain}:3000";
      icon = "si:adguard";
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

  # Prometheus returns value[1] as a numeric string; gjson coerces it for us.
  usageWidget = title: query: {
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
            {{ $pct := .Float "value.1" }}
            <li>
              <div class="flex justify-between">
                <span class="color-highlight text-truncate">{{ .String "metric.instance" }}</span>
                <span class="size-h5">{{ printf "%.0f%%" $pct }}</span>
              </div>
              <div style="height:3px;background:var(--color-separator);margin-top:4px;">
                <div style="height:3px;width:{{ printf "%.0f" $pct }}%;background:var(--color-primary);"></div>
              </div>
            </li>
          {{ end }}
        </ul>
      {{ end }}
    '';
  };

  alertsQuery = lib.concatStringsSep " or " [
    ''label_replace(100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > ${toString cfg.thresholds.cpu}, "alert", "cpu", "", "")''
    ''label_replace(100 * (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) > ${toString cfg.thresholds.memory}, "alert", "memory", "", "")''
    ''label_replace(100 * (1 - node_filesystem_avail_bytes{mountpoint="/",fstype!~"tmpfs|overlay|ramfs"} / node_filesystem_size_bytes{mountpoint="/",fstype!~"tmpfs|overlay|ramfs"}) > ${toString cfg.thresholds.disk}, "alert", "disk", "", "")''
    ''label_replace(up{job="node"} == 0, "alert", "down", "", "")''
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
            columns = [
              {
                size = "small";
                widgets = [
                  {
                    type = "bookmarks";
                    groups = map mkBookmarkGroup groupsInOrder;
                  }
                  {
                    type = "clock";
                    hour-format = "12h";
                  }
                ];
              }
              {
                size = "full";
                widgets = [
                  {
                    type = "custom-api";
                    title = "Needs Attention";
                    cache = "1m";
                    url = "${prometheus}/api/v1/query";
                    parameters.query = alertsQuery;
                    template = ''
                      {{ $results := .JSON.Array "data.result" }}
                      {{ if eq (len $results) 0 }}
                        <p class="color-positive size-h5">All hosts and services nominal</p>
                      {{ else }}
                        <ul class="list list-gap-10">
                          {{ range $results }}
                            {{ $kind := .String "metric.alert" }}
                            <li class="flex justify-between">
                              <span class="color-negative text-truncate">{{ .String "metric.instance" }}</span>
                              <span class="size-h6 color-subdue">
                                {{ if eq $kind "down" }}
                                  exporter down
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
                  (usageWidget "CPU Busy" ''topk(5, 100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100))'')
                  (usageWidget "Memory Used" "topk(5, 100 * (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes))")
                ];
              }
              {
                size = "small";
                widgets = [
                  {
                    type = "custom-api";
                    title = "Fleet";
                    cache = "1m";
                    url = "${prometheus}/api/v1/query";
                    parameters.query = ''sum(up{job="node"}) or vector(0)'';
                    template = ''
                      <div class="flex justify-between">
                        <span class="color-subdue">Hosts up</span>
                        <span class="size-h3 color-highlight">{{ (index (.JSON.Array "data.result") 0).Float "value.1" | printf "%.0f" }}</span>
                      </div>
                    '';
                  }
                  (usageWidget "Root Disk Used" ''topk(5, 100 * (1 - node_filesystem_avail_bytes{mountpoint="/",fstype!~"tmpfs|overlay|ramfs"} / node_filesystem_size_bytes{mountpoint="/",fstype!~"tmpfs|overlay|ramfs"}))'')
                ];
              }
            ];
          }
        ];
      };
    };
  };
}
