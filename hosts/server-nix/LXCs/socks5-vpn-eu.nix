{ self, networkTopology, ... }:
{
  imports = [
    ./base
    "${self}/modules/network/vpn-egress-client.nix"
    "${self}/modules/software/services/3proxy.nix"
  ];
  networking.hostName = "socks5-vpn-eu-nix";

  # Exits through the Swiss gateway instead of OPNsense's own Zurich tunnel.
  my.network.vpnEgress.client = {
    enable = true;
    gatewayAddress = networkTopology.lib.lanIp "networking-vpn-out-eu1-nix";
    normalGateway = networkTopology.networks.lan.gateway;
    bypassCidrs = [ networkTopology.networks.wgRemote.routedCidr ];
  };
}
