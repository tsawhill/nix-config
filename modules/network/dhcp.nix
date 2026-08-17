{
  config,
  lib,
  networkTopology,
  ...
}:

let
  cfg = config.my.networking.dhcp;
  lan = networkTopology.networks.lan;

  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    optional
    optionalAttrs
    types
    ;

  inherit (networkTopology.lib) lanIp;

  # Reservations are derived from the topology so a MAC/IP pair is declared in
  # exactly one place, the same way monitoring derives its scrape targets.
  reservationHosts = lib.filterAttrs (
    _: host: host ? lan && host.lan ? ip && host.lan ? mac
  ) networkTopology.hosts;

  topologyReservations = lib.mapAttrsToList (name: host: {
    inherit (host.lan) mac;
    ip = host.lan.ip;
    hostname = name;
  }) reservationHosts;

  reservationType = types.submodule {
    options = {
      mac = mkOption {
        type = types.str;
        description = "Client hardware address.";
      };
      ip = mkOption {
        type = types.str;
        description = "Address always handed to this client.";
      };
      hostname = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Hostname sent back to the client in option 12.";
      };
    };
  };
in
{
  options.my.networking.dhcp = {
    enable = mkEnableOption "Kea DHCPv4 server for the LAN";

    interface = mkOption {
      type = types.str;
      default = "eth0";
      description = "Interface Kea listens on for DHCP broadcasts.";
    };

    socketType = mkOption {
      type = types.enum [
        "raw"
        "udp"
      ];
      default = "raw";
      description = "Kea socket type; fall back to udp if the container cannot open AF_PACKET.";
    };

    subnet = mkOption {
      type = types.str;
      default = lan.cidr;
      description = "Served subnet in CIDR form.";
    };

    rangeStart = mkOption {
      type = types.str;
      default = lan.dhcpPool.start;
      description = "First address in the dynamic pool.";
    };

    rangeEnd = mkOption {
      type = types.str;
      default = lan.dhcpPool.end;
      description = "Last address in the dynamic pool.";
    };

    gateway = mkOption {
      type = types.str;
      default = lan.gateway;
      description = "Default gateway advertised to clients (option 3).";
    };

    dnsServers = mkOption {
      type = types.listOf types.str;
      default = [ (lanIp lan.dnsHost) ];
      description = "Resolvers advertised to clients (option 6).";
    };

    domain = mkOption {
      type = types.nullOr types.str;
      default = networkTopology.domains.dhcp;
      description = "Domain name advertised to clients (option 15).";
    };

    leaseTime = mkOption {
      type = types.int;
      default = 86400;
      description = "Lease valid-lifetime in seconds.";
    };

    renewTimer = mkOption {
      type = types.int;
      default = 21600;
      description = "T1, when a client first tries to renew.";
    };

    rebindTimer = mkOption {
      type = types.int;
      default = 43200;
      description = "T2, when a client starts broadcasting to rebind.";
    };

    authoritative = mkOption {
      type = types.bool;
      default = true;
      description = "NAK leases this server does not know about, instead of staying silent.";
    };

    reservations = mkOption {
      type = types.listOf reservationType;
      default = topologyReservations;
      defaultText = lib.literalMD "every topology host with both `lan.ip` and `lan.mac`";
      description = "Static DHCP reservations.";
    };

    extraOptionData = mkOption {
      type = types.listOf (types.attrsOf types.str);
      default = [ ];
      example = lib.literalExpression ''[ { name = "ntp-servers"; data = "10.73.73.1"; } ]'';
      description = "Additional Kea option-data entries appended to the subnet.";
    };
  };

  config = mkIf cfg.enable {
    services.kea.dhcp4 = {
      enable = true;
      settings = {
        valid-lifetime = cfg.leaseTime;
        renew-timer = cfg.renewTimer;
        rebind-timer = cfg.rebindTimer;
        inherit (cfg) authoritative;

        interfaces-config = {
          interfaces = [ cfg.interface ];
          dhcp-socket-type = cfg.socketType;
        };

        lease-database = {
          type = "memfile";
          persist = true;
          name = "/var/lib/kea/dhcp4.leases";
        };

        subnet4 = [
          {
            id = 1;
            subnet = cfg.subnet;
            interface = cfg.interface;
            pools = [ { pool = "${cfg.rangeStart} - ${cfg.rangeEnd}"; } ];

            reservations = map (
              reservation:
              {
                hw-address = reservation.mac;
                ip-address = reservation.ip;
              }
              // optionalAttrs (reservation.hostname != null) {
                inherit (reservation) hostname;
              }
            ) cfg.reservations;

            option-data =
              [
                {
                  name = "routers";
                  data = cfg.gateway;
                }
              ]
              ++ optional (cfg.dnsServers != [ ]) {
                name = "domain-name-servers";
                data = lib.concatStringsSep ", " cfg.dnsServers;
              }
              ++ optional (cfg.domain != null) {
                name = "domain-name";
                data = cfg.domain;
              }
              ++ cfg.extraOptionData;
          }
        ];
      };
    };

    networking.firewall.allowedUDPPorts = [ 67 ];
  };
}
