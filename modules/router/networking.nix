{ config, lib, ... }:

let
  cfg = config.my.router;

  inherit (lib)
    attrValues
    filterAttrs
    mapAttrs
    mkDefault
    mkIf
    optionalAttrs
    ;

  interfaces = attrValues cfg.interfaces;
  lanInterfaces = builtins.filter (iface: iface.role == "lan" || iface.role == "internal") interfaces;
  wanInterfaces = builtins.filter (iface: iface.role == "wan") interfaces;

  # systemd-networkd owns every router-facing interface. WAN DHCP is client-only;
  # LAN/static interfaces get explicit addresses and never accept IPv6 RA here.
  mkNetwork = _name: iface: {
    matchConfig.Name = iface.name;
    networkConfig =
      optionalAttrs (iface.address != null && iface.prefixLength != null) {
        Address = "${iface.address}/${toString iface.prefixLength}";
      }
      // optionalAttrs iface.dhcpClient {
        DHCP = "ipv4";
      }
      // {
        IPv6AcceptRA = false;
        LinkLocalAddressing = "no";
      };
    dhcpV4Config = optionalAttrs iface.dhcpClient {
      UseDNS = false;
      UseDomains = false;
    };
    linkConfig.RequiredForOnline = iface.requiredForOnline;
  };
in
{
  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = wanInterfaces != [ ];
        message = "my.router requires at least one interface with role = \"wan\".";
      }
      {
        assertion = lanInterfaces != [ ];
        message = "my.router requires at least one interface with role = \"lan\" or \"internal\".";
      }
    ];

    # This module is IPv4 router-oriented for now. Interfaces disable RA below;
    # full host-wide IPv6 policy should stay with the importing machine config.
    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = mkDefault 1;
    };

    networking = {
      useDHCP = false;
      useNetworkd = true;
    };

    systemd.network = {
      enable = true;
      networks = mapAttrs mkNetwork cfg.interfaces;
    };
  };
}
