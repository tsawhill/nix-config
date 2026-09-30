# Inter-zone policy, enforced on networking-router-nix.
# Zones are topology.zones plus "legacy" (the flat 10.73.73.0/24 LAN), "vpn"
# (WireGuard peers behind networking-vpn-in-nix, already filtered per peer there)
# and "internet". Replies are always allowed; this lists who may open connections.
# Every zone may also reach AdGuard DNS.
{
  allow = {
    trusted = [
      "legacy"
      "networking"
      "services"
      "guests"
      "iot"
      "vpn"
      "internet"
    ];
    networking = [
      "legacy"
      "internet"
    ];
    services = [
      "legacy"
      "internet"
    ];
    guests = [ "internet" ];
    iot = [ ];
    # Matches today's flat LAN until it is emptied into the zones.
    legacy = [
      "trusted"
      "networking"
      "services"
      "iot"
      "vpn"
      "internet"
    ];
    vpn = [
      "legacy"
      "trusted"
      "networking"
      "services"
      "iot"
      "internet"
    ];
  };

  # Single hosts allowed into a zone their own zone can't reach.
  hostAllow = [
    {
      host = "homeassistant-nix";
      to = "iot";
    }
  ];

  # Never reach the internet, whichever zone they are in. VPN egress clients
  # (arrs, qbit-*, searx, socks5, unbound-vpn-na) are added automatically.
  noInternet = [
    "amcrest-cameras"
    "ac-controller-office"
    "ac-controller-bedroom"
    "ac-controller-livingroom"
  ];

  # Inbound from the WAN address, hairpinned for LAN clients too.
  portForwards = [
    {
      host = "networking-vpn-in-nix";
      protocol = "udp";
      port = 51820;
    }
  ];
}
