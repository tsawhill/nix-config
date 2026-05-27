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

  mkProfile = name: srv: {
    connection = {
      id = "wg-airvpn-${name}";
      type = "wireguard";
      interface-name = "wg-airvpn";
      autoconnect = if cfg.autoconnect == name then "true" else "false";
    };
    wireguard = {
      private-key = "$WG_AIRVPN_PRIVATE_KEY";
      private-key-flags = "0";
      mtu = toString airvpn.mtu;
    };
    "wireguard-peer.${airvpn.publicKey}" = {
      preshared-key = "$WG_AIRVPN_PRESHARED_KEY";
      preshared-key-flags = "0";
      endpoint = "${srv.ip}:${toString airvpn.port}";
      allowed-ips = "0.0.0.0/0;::/0;";
      persistent-keepalive = "15";
    };
    ipv4 = {
      method = "manual";
      address1 = cfg.address;
      dns = "${airvpn.dns.ipv4};";
    };
    ipv6 = {
      method = "disabled";
    };
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

    autoconnect = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Server name to autoconnect to (must be in selection)";
    };
};

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.autoconnect == null || selectedServers ? ${cfg.autoconnect};
        message = "my.network.airvpn.autoconnect: server \"${toString cfg.autoconnect}\" is not in the selected servers";
      }
    ];
    sops.templates."nm-airvpn-env" = {
      content = ''
        WG_AIRVPN_PRIVATE_KEY=${config.sops.placeholder.wg_airvpn_private_key}
        WG_AIRVPN_PRESHARED_KEY=${config.sops.placeholder.wg_airvpn_preshared_key}
      '';
    };

    networking.networkmanager.ensureProfiles = {
      environmentFiles = [
        config.sops.templates."nm-airvpn-env".path
      ];
      profiles = lib.mapAttrs' (
        name: srv: lib.nameValuePair "wg-airvpn-${name}" (mkProfile name srv)
      ) selectedServers;
    };
  };
}
