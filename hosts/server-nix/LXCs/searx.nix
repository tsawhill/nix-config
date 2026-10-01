{
  self,
  networkTopology,
  ...
}:

let
  vpnClientEnabled = true;
in
{
  imports = [
    ./base
    "${self}/modules/network/vpn-egress-client.nix"
    "${self}/modules/software/services/searx.nix"
    "${self}/modules/software/services/searx-vpn-watchdog.nix"
  ];
  networking.hostName = "searx-nix";
  my.secrets.searx_secret_key.enable = true;

  my.network.vpnEgress.client = {
    enable = vpnClientEnabled;
    gatewayAddress = networkTopology.lib.lanIp "networking-vpn-out-na1-nix";
    normalGateway = networkTopology.networks.lan.gateway;
    bypassCidrs = [ networkTopology.networks.wgRemote.routedCidr ];
  };

  my.services.searxVpnWatchdog = {
    enable = vpnClientEnabled;
    gatewayHost = networkTopology.lib.fqdn "networking-vpn-out-na1-nix";
  };
}
