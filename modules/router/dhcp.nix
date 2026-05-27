{ config, lib, ... }:

let
  cfg = config.my.router;

  inherit (lib)
    attrValues
    filterAttrs
    imap0
    mkIf
    optional
    optionalAttrs
    ;

  enabledDhcpInterfaces = attrValues (filterAttrs (_: iface: iface.dhcp.enable) cfg.interfaces);

  # Kea has one daemon/config file, but this module treats DHCP as an
  # interface-local feature and folds all enabled interfaces into subnet4.
  mkKeaSubnet =
    idx: iface:
    {
      id = idx + 1;
      subnet = iface.dhcp.subnet;
      interface = iface.name;
      pools = [
        {
          pool = "${iface.dhcp.rangeStart} - ${iface.dhcp.rangeEnd}";
        }
      ];
      reservations = map (
        reservation:
        {
          hw-address = reservation.mac;
          ip-address = reservation.ip;
        }
        // optionalAttrs (reservation.hostname != null) {
          hostname = reservation.hostname;
        }
      ) iface.dhcp.reservations;
      option-data =
        [
          {
            name = "routers";
            data = iface.dhcp.gateway;
          }
        ]
        ++ optional (iface.dhcp.dnsServers != [ ]) {
          name = "domain-name-servers";
          data = lib.concatStringsSep ", " iface.dhcp.dnsServers;
        }
        ++ optional (iface.dhcp.domain != null) {
          name = "domain-name";
          data = iface.dhcp.domain;
        };
    };
in
{
  config = mkIf cfg.enable {
    assertions = map (iface: {
      assertion =
        !iface.dhcp.enable
        || (
          iface.dhcp.subnet != null
          && iface.dhcp.rangeStart != null
          && iface.dhcp.rangeEnd != null
          && iface.dhcp.gateway != null
        );
      message = "my.router.interfaces.${iface.name}.dhcp requires subnet, rangeStart, rangeEnd, and gateway.";
    }) enabledDhcpInterfaces;

    services.kea.dhcp4 = mkIf (enabledDhcpInterfaces != [ ]) {
      enable = true;
      settings = {
        valid-lifetime = 86400;
        renew-timer = 21600;
        rebind-timer = 43200;
        interfaces-config.interfaces = map (iface: iface.name) enabledDhcpInterfaces;
        lease-database = {
          type = "memfile";
          persist = true;
          name = "/var/lib/kea/dhcp4.leases";
        };
        subnet4 = imap0 mkKeaSubnet enabledDhcpInterfaces;
      };
    };
  };
}
