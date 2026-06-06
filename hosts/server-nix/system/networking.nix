{ networkTopology, ... }:
let
  inherit (networkTopology.lib) lanIp;
in
{
  services.resolved = {
    enable = true;
    fallbackDns = [ "9.9.9.9" ];
  };

  # Needed for routing on WAN
  boot.kernel.sysctl = {
    "net.bridge.bridge-nf-call-iptables" = 0;
    "net.bridge.bridge-nf-call-arptables" = 0;
    "net.bridge.bridge-nf-call-ip6tables" = 0;
  };
  networking = {
    useDHCP = false;
    useNetworkd = true;
    nameservers = [
      (lanIp networkTopology.networks.lan.dnsHost)
    ];
  };

  boot.kernelParams = [
    "net.ifnames=0"
    "ipv6.disable=1"
  ];

  systemd.network = {
    enable = true;

    # ┌───────────────────────────────────────────────────────────────────────┐
    # │ Physical Interface Links (Renaming to lan0 and wan0)                  │
    # └───────────────────────────────────────────────────────────────────────┘

    # LAN port
    links."10-lan0" = {
      matchConfig.MACAddress = "e4:1d:2d:7e:e5:20";
      linkConfig = {
        Name = "lan0";
        NamePolicy = "none";
      };
    };

    # WAN port
    links."11-wan0" = {
      matchConfig.MACAddress = "9c:6b:00:13:95:4e";
      linkConfig = {
        Name = "wan0";
        NamePolicy = "none";
      };
    };

    # ┌───────────────────────────────────────────────────────────────────────┐
    # │ Bridge Netdev Definitions (Creating br0 and br1)                      │
    # └───────────────────────────────────────────────────────────────────────┘

    # LAN bridge
    netdevs."20-br0".netdevConfig = {
      Kind = "bridge";
      Name = "br0";
    };

    # WAN bridge
    netdevs."21-br1".netdevConfig = {
      Kind = "bridge";
      Name = "br1";
    };

    # ┌───────────────────────────────────────────────────────────────────────┐
    # │ Interface Bindings (Plugging Physical Ports into Bridges)             │
    # └───────────────────────────────────────────────────────────────────────┘

    # LAN interface binding
    networks."30-lan0" = {
      matchConfig.Name = "lan0";
      networkConfig.Bridge = "br0";
      linkConfig.RequiredForOnline = "enslaved";
    };

    # WAN interface binding
    networks."31-wan0" = {
      matchConfig.Name = "wan0";
      networkConfig.Bridge = "br1";
      linkConfig.RequiredForOnline = "enslaved";
    };

    # ┌───────────────────────────────────────────────────────────────────────┐
    # │ Bridge IP Configurations (LAN Management & WAN Passthrough)           │
    # └───────────────────────────────────────────────────────────────────────┘

    # Static LAN connection
    networks."40-br0" = {
      matchConfig.Name = "br0";
      networkConfig = {
        Address = "${lanIp "server-nix"}/24";
        Gateway = networkTopology.networks.lan.gateway;
        DNS = [
          (lanIp networkTopology.networks.lan.dnsHost)
        ];
      };
      linkConfig.RequiredForOnline = "routable";
    };

    # No config on WAN port
    networks."41-br1" = {
      matchConfig.Name = "br1";
      # No IP assigned to the host on the WAN bridge
      networkConfig = {
        DHCP = "no";
        IPv6AcceptRA = false;
        LinkLocalAddressing = "no";
      };
      # We don't want the boot process to hang waiting for br1 to get an IP
      linkConfig.RequiredForOnline = "no";
    };

    # ┌───────────────────────────────────────────────────────────────────────┐
    # │ Catch-all for USB tethering                                           │
    # └───────────────────────────────────────────────────────────────────────┘

    networks."50-usb-tether" = {
      # Match standard USB network interface names
      # With net.ifnames=0, this is usually "usb0"
      matchConfig.Name = "usb*";

      networkConfig = {
        DHCP = "yes";
        # Optional: Set a metric if you want to prioritize this over LAN/WAN
        # RouteMetric = 10;
      };
    };
  };
}
