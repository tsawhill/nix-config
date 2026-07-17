{ config, lib, ... }:

let
  cfg = config.my.network.networkmanager.wifi;

  defaultNetworks = {
    home = {
      ssidSecret = "home_ssid";
      pskSecret = "home_psk";
    };
    parents = {
      ssidSecret = "parents_ssid";
      pskSecret = "parents_psk";
    };
    sisters = {
      ssidSecret = "sisters_ssid";
      pskSecret = "sisters_psk";
    };
  };

  boolToString = value: if value then "true" else "false";

  mkOptionalLine =
    condition: line:
    lib.optionalString condition "${line}\n";

  mkConnection =
    name: profile:
    let
      prioritySection = mkOptionalLine (
        profile.autoconnectPriority != null
      ) "autoconnect-priority=${toString profile.autoconnectPriority}";

      ipv4DnsPrioritySection = mkOptionalLine (
        profile.ipv4.dnsPriority != null
      ) "dns-priority=${toString profile.ipv4.dnsPriority}";

      ipv4RouteMetricSection = mkOptionalLine (
        profile.ipv4.routeMetric != null
      ) "route-metric=${toString profile.ipv4.routeMetric}";
    in
    {
      path = "/etc/NetworkManager/system-connections/wifi-${name}.nmconnection";
      owner = "root";
      group = "root";
      mode = "0600";
      content = ''
        [connection]
        id=${profile.id}
        type=wifi
        autoconnect=${boolToString profile.autoconnect}
        ${prioritySection}
        [wifi]
        mode=infrastructure
        ssid=${config.sops.placeholder.${profile.ssidSecret}}
        hidden=${boolToString profile.hidden}

        [wifi-security]
        key-mgmt=wpa-psk
        psk=${config.sops.placeholder.${profile.pskSecret}}
        psk-flags=0

        [ipv4]
        method=${profile.ipv4.method}
        ${ipv4DnsPrioritySection}${ipv4RouteMetricSection}
        [ipv6]
        method=${profile.ipv6.method}
      '';
    };
in
{
  options.my.network.networkmanager.wifi = {
    enable = lib.mkEnableOption "known Wi-Fi NetworkManager profiles";

    networks = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }:
          {
            options = {
              id = lib.mkOption {
                type = lib.types.str;
                default = name;
                description = "Public NetworkManager connection id.";
              };

              ssidSecret = lib.mkOption {
                type = lib.types.str;
                description = "sops secret name containing the Wi-Fi SSID.";
              };

              pskSecret = lib.mkOption {
                type = lib.types.str;
                description = "sops secret name containing the Wi-Fi passphrase.";
              };

              autoconnect = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = "Whether NetworkManager should autoconnect this profile.";
              };

              autoconnectPriority = lib.mkOption {
                type = lib.types.nullOr lib.types.int;
                default = null;
                description = "NetworkManager autoconnect priority.";
              };

              hidden = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = "Whether the SSID is hidden.";
              };

              ipv4 = {
                method = lib.mkOption {
                  type = lib.types.enum [
                    "auto"
                    "disabled"
                    "link-local"
                    "manual"
                    "shared"
                  ];
                  default = "auto";
                };

                dnsPriority = lib.mkOption {
                  type = lib.types.nullOr lib.types.int;
                  default = null;
                };

                routeMetric = lib.mkOption {
                  type = lib.types.nullOr lib.types.int;
                  default = null;
                };
              };

              ipv6.method = lib.mkOption {
                type = lib.types.enum [
                  "auto"
                  "disabled"
                  "ignore"
                  "link-local"
                  "manual"
                  "shared"
                ];
                default = "auto";
              };
            };
          }
        )
      );
      default = defaultNetworks;
      description = "Known Wi-Fi profiles keyed by file-safe profile id.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.all (
          name: builtins.match "^[A-Za-z0-9._-]+$" name != null
        ) (builtins.attrNames cfg.networks);
        message = "my.network.networkmanager.wifi.networks keys must only contain letters, numbers, dot, underscore, or dash";
      }
    ];

    sops.templates = lib.mapAttrs' (
      name: profile: lib.nameValuePair "nm-wifi-${name}" (mkConnection name profile)
    ) cfg.networks;

    systemd.services.NetworkManager.restartTriggers =
      lib.mapAttrsToList (
        name: _profile: config.sops.templates."nm-wifi-${name}".content
      ) cfg.networks;
  };
}
