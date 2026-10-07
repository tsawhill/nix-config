{ self, networkTopology, ... }:

{
  imports = [
    ./base
    "${self}/modules/network/vpn-egress-client.nix"
    "${self}/modules/software/services/searx.nix"
  ];
  networking.hostName = "searx-nix";
  my.secrets.searx_secret_key.enable = true;

  # Google CSE answers fine from VPN exits, so Google never sees the home IP.
  my.network.vpnEgress.client = {
    enable = true;
    gatewayAddress = networkTopology.lib.lanIp "networking-vpn-out-na1-nix";
    normalGateway = networkTopology.networks.lan.gateway;
    bypassCidrs = [ networkTopology.networks.wgRemote.routedCidr ];
  };
}
