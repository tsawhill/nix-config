# Inter-zone policy, enforced on networking-router-nix.
# Zones are topology.zones plus "legacy" (the flat 10.73.73.0/24 LAN and anything
# behind OPNsense) and "internet". Replies are always allowed; this lists who may
# open connections. Every zone may also reach AdGuard DNS.
{
  allow = {
    trusted = [
      "legacy"
      "networking"
      "services"
      "guests"
      "iot"
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
    ];
  };

  # Single hosts allowed into a zone their own zone can't reach.
  hostAllow = [
    {
      host = "homeassistant-nix";
      to = "iot";
    }
  ];
}
