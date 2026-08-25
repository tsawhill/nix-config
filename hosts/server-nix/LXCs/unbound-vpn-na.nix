{
  networkTopology,
  self,
  ...
}:
{
  imports = [
    ./base
    "${self}/modules/network/vpn-egress-client.nix"
    "${self}/modules/software/services/unbound.nix"
  ];
  networking.hostName = "unbound-vpn-na-nix";

  my.network.vpnEgress.client = {
    enable = true;
    gatewayAddress = networkTopology.lib.lanIp "networking-vpn-out-na1-nix";
    normalGateway = networkTopology.networks.lan.gateway;
    bypassCidrs = [ networkTopology.networks.wgRemote.routedCidr ];
  };
}
