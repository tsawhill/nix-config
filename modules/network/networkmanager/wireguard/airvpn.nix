{ config, lib, ... }:

let
  cfg = config.my.network.airvpn;
  airvpn = import ./airvpn-servers.nix;

  selectedServers = lib.filterAttrs (
    name: srv:
    builtins.elem srv.country cfg.countries
    || builtins.elem srv.city cfg.cities
    || builtins.elem name cfg.servers
  ) airvpn.servers;

  endpoints = lib.mapAttrsToList (name: srv: {
    inherit name;
    inherit (srv) ip;
    port = airvpn.port;
    connectionId = "wg-airvpn-${name}";
  }) selectedServers;

  peerPublicKey =
    if cfg.peerPublicKey == null then config.sops.placeholder.wg_pubkey_airvpn else cfg.peerPublicKey;
  privateKey = config.sops.placeholder.${cfg.privateKeySecret};
  presharedKey = config.sops.placeholder.${cfg.presharedKeySecret};

  dnsSection = lib.optionalString (cfg.dns != null) ''
    dns=${cfg.dns};
  '';
  policyRouteSection = lib.optionalString (cfg.routeTable != null) ''
    route1=0.0.0.0/0,,10
    route1_options=table=${toString cfg.routeTable}
  '';

  mkTemplate = name: srv: {
    path = "/etc/NetworkManager/system-connections/wg-airvpn-${name}.nmconnection";
    owner = "root";
    group = "root";
    mode = "0600";
    content = ''
      [connection]
      id=wg-airvpn-${name}
      type=wireguard
      interface-name=${cfg.interfaceName}
      autoconnect=${if cfg.autoconnect == name then "true" else "false"}

      [wireguard]
      private-key=${privateKey}
      private-key-flags=0
      peer-routes=${if cfg.peerRoutes then "true" else "false"}
      mtu=${toString airvpn.mtu}

      [wireguard-peer.${peerPublicKey}]
      preshared-key=${presharedKey}
      preshared-key-flags=0
      endpoint=${srv.ip}:${toString airvpn.port}
      allowed-ips=${cfg.allowedIPs}
      persistent-keepalive=15

      [ipv4]
      method=manual
      address1=${cfg.address}
      never-default=${if cfg.neverDefault then "true" else "false"}
      ${dnsSection}${policyRouteSection}

      [ipv6]
      method=disabled
    '';
  };
in
{
  options.my.network.airvpn = {
    enable = lib.mkEnableOption "AirVPN WireGuard NM profiles";

    countries = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Country codes to include (e.g. US, CA, JP)";
    };

    cities = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "City names to include (e.g. Tokyo, London)";
    };

    servers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Server names to include (e.g. Maia, Bharani)";
    };

    address = lib.mkOption {
      type = lib.types.str;
      description = "Device tunnel IPv4 address with prefix (e.g. 10.134.43.233/32)";
    };

    interfaceName = lib.mkOption {
      type = lib.types.str;
      default = "wg-airvpn";
      description = "NetworkManager WireGuard interface shared by the selected AirVPN profiles.";
    };

    peerPublicKey = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "AirVPN peer public key. Null preserves the shared wg_pubkey_airvpn secret used by existing hosts.";
    };

    privateKeySecret = lib.mkOption {
      type = lib.types.str;
      default = "wg_airvpn_private_key";
      description = "SOPS secret name containing this AirVPN device's private key.";
    };

    presharedKeySecret = lib.mkOption {
      type = lib.types.str;
      default = "wg_airvpn_preshared_key";
      description = "SOPS secret name containing this AirVPN device's preshared key.";
    };

    allowedIPs = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0/0;::/0;";
      description = "Semicolon-separated WireGuard allowed IPs for NetworkManager.";
    };

    dns = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "${airvpn.dns.ipv4};";
      description = "DNS servers placed in each profile, or null to retain underlay DNS.";
    };

    peerRoutes = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether NetworkManager automatically installs routes for the peer allowed IPs.";
    };

    neverDefault = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Prevent NetworkManager from treating the profile as the main default connection.";
    };

    routeTable = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      description = "Optional policy-routing table receiving an explicit VPN default route.";
    };

    autoconnect = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Server name to autoconnect to (must be in selection)";
    };

    endpoints = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption { type = lib.types.str; };
            ip = lib.mkOption { type = lib.types.str; };
            port = lib.mkOption { type = lib.types.port; };
            connectionId = lib.mkOption { type = lib.types.str; };
          };
        }
      );
      default = endpoints;
      readOnly = true;
      description = "Selected AirVPN NetworkManager profiles for health-driven consumers.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.autoconnect == null || selectedServers ? ${cfg.autoconnect};
        message = "my.network.airvpn.autoconnect: server \"${toString cfg.autoconnect}\" is not in the selected servers";
      }
      {
        assertion = selectedServers != { };
        message = "my.network.airvpn must select at least one server, city, or country.";
      }
      {
        assertion = cfg.routeTable == null || (!cfg.peerRoutes && cfg.neverDefault);
        message = "my.network.airvpn.routeTable requires peerRoutes = false and neverDefault = true.";
      }
    ];

    sops.templates = lib.mapAttrs' (
      name: srv: lib.nameValuePair "nm-wg-airvpn-${name}" (mkTemplate name srv)
    ) selectedServers;

    systemd.services.NetworkManager.restartTriggers = lib.mapAttrsToList (
      name: _srv: config.sops.templates."nm-wg-airvpn-${name}".content
    ) selectedServers;
  };
}
