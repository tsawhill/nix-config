{
  config,
  lib,
  networkTopology,
  pkgs,
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
      name = "qui";
      url = "https://qbit.tsawhill.org";
      icon = "sh:qbittorrent";
      group = "Arrs";
      altStatus = [
        302
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
      url = "http://adguard-nix.${lanDomain}";
      icon = "sh:adguard-home";
      group = "Monitoring";
    }
    {
      name = "qBittorrent intake";
      url = "http://qbit-gen-nix.${lanDomain}:8080";
      icon = "sh:qbittorrent";
      group = "Infra";
    }
    {
      name = "qBittorrent seeding";
      url = "http://qbit-lts-nix.${lanDomain}:8080";
      icon = "sh:qbittorrent";
      group = "Infra";
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

  # Listed groups come first in the order given; anything unlisted keeps its
  # definition order and lands at the bottom.
  groupsInOrder =
    links:
    let
      present = lib.unique (map (s: s.group) links);
    in
    lib.filter (g: lib.elem g present) cfg.groupOrder
    ++ lib.filter (g: !lib.elem g cfg.groupOrder) present;

  sortByGroup = links: lib.concatMap (g: lib.filter (s: s.group == g) links) (groupsInOrder links);

  # Services link from their monitor tiles, so bookmarks only carry the rest.
  mkBookmarkGroup = group: {
    title = group;
    links = map (s: {
      title = s.name;
      url = s.url;
      icon = s.icon or "";
    }) (lib.filter (s: s.group == group) cfg.internalLinks);
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
  memoryPercent = "100 * (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)";
  rootFilesystemFilter = ''mountpoint="/",fstype!~"tmpfs|overlay|ramfs"'';
  rootPercent = "100 * (1 - node_filesystem_avail_bytes{${rootFilesystemFilter}} / node_filesystem_size_bytes{${rootFilesystemFilter}})";

  # "worst" only exists to sort hosts by their most stressed resource.
  hostsQuery = multiMeasurementQuery [
    (asMeasurement "cpu" cpuBusy)
    (asMeasurement "memory" memoryPercent)
    (asMeasurement "disk" rootPercent)
    (asMeasurement "worst" "max by (instance) (${cpuBusy} or ${memoryPercent} or ${rootPercent})")
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

  # Go templates refuse to compare a float against an int literal.
  asFloat = n: "${toString n}.0";

  # Expects the percentage in $pct; turns red past the threshold.
  usageBar = threshold: ''
    <div style="height:3px;background:var(--color-separator);margin-top:4px;">
      <div style="height:3px;width:{{ printf "%.0f" $pct }}%;background:{{ if gt $pct ${asFloat threshold} }}var(--color-negative){{ else }}var(--color-primary){{ end }};"></div>
    </div>
  '';

  hostsGrid = "display:grid;grid-template-columns:minmax(0,1.6fr) repeat(3,minmax(0,1fr));gap:14px;align-items:end;";

  hostCell = measurement: threshold: ''
    <div>
      {{- range $results -}}
        {{- if and (eq (.String "metric.instance") $instance) (eq (.String "metric.measurement") "${measurement}") -}}
          {{- $pct := .Float "value.1" -}}
          <div class="size-h6{{ if gt $pct ${asFloat threshold} }} color-negative{{ end }}">{{ printf "%.0f%%" $pct }}</div>
          ${usageBar threshold}
        {{- end -}}
      {{- end -}}
    </div>
  '';

  # Prometheus returns value[1] as a numeric string; gjson coerces it for us.
  hostsWidget = {
    type = "custom-api";
    title = "Hosts";
    cache = "1m";
    url = "${prometheus}/api/v1/query";
    parameters.query = hostsQuery;
    template = ''
      {{ $results := .JSON.Array "data.result" }}
      {{ if eq (len $results) 0 }}
        <p class="color-subdue">no data</p>
      {{ else }}
        <div class="size-h6 color-subdue" style="${hostsGrid}margin-bottom:10px;">
          <span>Host</span><span>CPU</span><span>Memory</span><span>Disk</span>
        </div>
        <ul class="list list-gap-10 collapsible-container" data-collapse-after="8">
          {{ range sortByFloat "value.1" "desc" $results }}
            {{ if eq (.String "metric.measurement") "worst" }}
              {{ $instance := .String "metric.instance" }}
              <li style="${hostsGrid}">
                <span class="color-highlight text-truncate">{{ $instance }}</span>
                ${hostCell "cpu" cfg.thresholds.cpu}
                ${hostCell "memory" cfg.thresholds.memory}
                ${hostCell "disk" cfg.thresholds.disk}
              </li>
            {{ end }}
          {{ end }}
        </ul>
      {{ end }}
    '';
  };

  zfsWidget = {
    type = "custom-api";
    title = "Server ZFS Pools";
    cache = "1m";
    url = "${prometheus}/api/v1/query";
    parameters.query = zfsQuery;
    template = ''
      {{ $results := .JSON.Array "data.result" }}
      {{ if eq (len $results) 0 }}
        <p class="color-subdue">no data</p>
      {{ else }}
        <ul class="list list-gap-10">
          {{ range $results }}
            {{ if eq (.String "metric.measurement") "percent" }}
              {{ $name := .String "metric.pool" }}
              {{ $pct := .Float "value.1" }}
              <li>
                <div class="flex justify-between">
                  <span class="color-highlight text-truncate">{{ $name }}</span>
                  {{ range $results }}
                    {{ if and (eq (.String "metric.pool") $name) (eq (.String "metric.measurement") "online") }}
                      {{ if eq (.String "value.1") "1" }}
                        <span class="size-h6 color-positive">ONLINE</span>
                      {{ else }}
                        <span class="size-h6 color-negative">NOT ONLINE</span>
                      {{ end }}
                    {{ end }}
                  {{ end }}
                </div>
                <div class="flex justify-end size-h5">
                  <span>
                    {{- range $results -}}
                      {{- if and (eq (.String "metric.pool") $name) (eq (.String "metric.measurement") "used") -}}
                        {{- printf "%.1f/" (.Float "value.1") -}}
                      {{- end -}}
                    {{- end -}}
                    {{- range $results -}}
                      {{- if and (eq (.String "metric.pool") $name) (eq (.String "metric.measurement") "total") -}}
                        {{- printf "%.1f" (.Float "value.1") -}}
                      {{- end -}}
                    {{- end -}}
                    TiB ({{ printf "%.0f%%" $pct }})
                  </span>
                </div>
                ${usageBar cfg.thresholds.zfs}
              </li>
            {{ end }}
          {{ end }}
        </ul>
      {{ end }}
    '';
  };

  # fleet-* rows feed the header line; every other row is an alert.
  statusQuery = lib.concatStringsSep " or " [
    ''label_replace(sum(up{job="node",instance!~"${intermittentHostRegex}"}) or vector(0), "alert", "fleet-up", "", "")''
    ''label_replace(count(up{job="node",instance!~"${intermittentHostRegex}"}) or vector(0), "alert", "fleet-total", "", "")''
    ''label_replace(${cpuBusy} > ${toString cfg.thresholds.cpu}, "alert", "cpu", "", "")''
    ''label_replace(${memoryPercent} > ${toString cfg.thresholds.memory}, "alert", "memory", "", "")''
    ''label_replace(${rootPercent} > ${toString cfg.thresholds.disk}, "alert", "disk", "", "")''
    ''label_replace(up{job="node",instance!~"${intermittentHostRegex}"} == 0, "alert", "down", "", "")''
    ''label_replace(node_zfs_zpool_state{instance="server-nix",state!="online",zpool=~"${zfsPoolRegex}"} == 1, "alert", "zpool", "", "")''
    ''label_replace(vpn_egress_tunnel_up{instance="networking-vpn-out-na1-nix"} == 0, "alert", "vpn", "", "")''
    ''label_replace(searx_vpn_backoff_active{instance="searx-nix"} == 1, "alert", "searx-vpn", "", "")''
  ];

  statusWidget = {
    type = "custom-api";
    title = "Status";
    cache = "1m";
    url = "${prometheus}/api/v1/query";
    parameters.query = statusQuery;
    template = ''
      {{ $results := .JSON.Array "data.result" }}
      {{ $up := 0.0 }}
      {{ $total := 0.0 }}
      {{ $clear := true }}
      {{ range $results }}
        {{ $kind := .String "metric.alert" }}
        {{ if eq $kind "fleet-up" }}
          {{ $up = .Float "value.1" }}
        {{ else if eq $kind "fleet-total" }}
          {{ $total = .Float "value.1" }}
        {{ else }}
          {{ $clear = false }}
        {{ end }}
      {{ end }}
      <div class="flex justify-between items-center">
        {{ if $clear }}
          <span class="size-h3 color-positive">All clear</span>
        {{ else }}
          <span class="size-h3 color-negative">Needs attention</span>
        {{ end }}
        <span class="color-subdue">{{ printf "%.0f/%.0f" $up $total }} hosts up</span>
      </div>
      {{ if not $clear }}
        <ul class="list list-gap-10" style="margin-top:12px;">
          {{ range $results }}
            {{ $kind := .String "metric.alert" }}
            {{ if and (ne $kind "fleet-up") (ne $kind "fleet-total") }}
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
          {{ end }}
        </ul>
      {{ end }}
    '';
  };

  # Glance only refreshes stale widgets when a page is requested, so poll it
  # ourselves and visitors always land on a warm cache.
  cacheWarmer = pkgs.writeShellScript "glance-cache-warmer" ''
    while true; do
      ${lib.getExe pkgs.curl} -s -o /dev/null --max-time 30 http://127.0.0.1:${toString cfg.port}/api/pages/home/content/ || true
      sleep ${toString cfg.warmInterval}
    done
  '';
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
      description = "Externally reachable services to health-check; their monitor tiles double as links.";
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
      description = "Order bookmark groups and monitor tiles are rendered in; unlisted groups are appended.";
    };

    internalLinks = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      default = defaultInternalLinks;
      description = "Pages to link but not health-check: LAN-only admin UIs, hosts that are usually off, and everyday external sites.";
    };

    releaseRepos = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "glanceapp/glance"
        "jellyfin/jellyfin"
        "immich-app/immich"
        "goauthentik/authentik"
        "Sonarr/Sonarr"
        "Radarr/Radarr"
        "Prowlarr/Prowlarr"
        "open-webui/open-webui"
        "dani-garcia/vaultwarden"
        "nextcloud/server"
      ];
      description = "GitHub repositories whose latest releases are listed.";
    };

    weather = {
      location = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Location for the weather widget; the widget is hidden when null.";
      };
      units = lib.mkOption {
        type = lib.types.enum [
          "metric"
          "imperial"
        ];
        default = "imperial";
        description = "Units for the weather widget.";
      };
    };

    warmInterval = lib.mkOption {
      type = lib.types.ints.positive;
      default = 15;
      description = "Seconds between background requests that keep widget caches fresh.";
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
      zfs = lib.mkOption {
        type = lib.types.int;
        default = 80;
        description = "ZFS pool used percent above which its bar turns red.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.glance-cache-warmer = {
      description = "Keep Glance widget caches warm";
      after = [ "glance.service" ];
      bindsTo = [ "glance.service" ];
      wantedBy = [ "glance.service" ];
      serviceConfig = {
        ExecStart = cacheWarmer;
        DynamicUser = true;
        Restart = "always";
      };
    };

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
                    groups = map mkBookmarkGroup (groupsInOrder cfg.internalLinks);
                  }
                  {
                    type = "releases";
                    cache = "6h";
                    collapse-after = 5;
                    repositories = cfg.releaseRepos;
                  }
                ];
              }
              {
                size = "full";
                widgets = [
                  statusWidget
                  {
                    type = "monitor";
                    title = "Services";
                    style = "compact";
                    cache = "2m";
                    sites = map mkMonitorSite (sortByGroup cfg.services);
                  }
                  hostsWidget
                ];
              }
              {
                size = "small";
                widgets = [
                  {
                    type = "clock";
                    hour-format = "12h";
                  }
                ]
                ++ lib.optional (cfg.weather.location != null) {
                  type = "weather";
                  inherit (cfg.weather) location units;
                  hour-format = "12h";
                }
                ++ [
                  {
                    type = "dns-stats";
                    service = "adguard";
                    url = "http://adguard-nix.${lanDomain}";
                    hour-format = "12h";
                    cache = "5m";
                  }
                  zfsWidget
                ];
              }
            ];
          }
        ];
      };
    };
  };
}
