{
  self,
  inputs,
  networkTopology,
  ...
}:

let
  # Enable only after networking-vpn-out-na1-nix is provisioned, has a verified
  # tunnel, and has passed the no-leak acceptance check.
  vpnClientEnabled = false;
in
{
  imports = [
    ./base
    "${self}/modules/network/vpn-egress-client.nix"
    "${self}/modules/software/services/searx.nix"
  ];
  networking.hostName = "searx-nix";
  my.secrets.searx_secret_key.enable = true;
  services.searx.package = inputs.nixpkgs-master.legacyPackages.x86_64-linux.searxng;

  my.network.vpnEgress.client = {
    enable = vpnClientEnabled;
    gatewayAddress = networkTopology.lib.lanIp "networking-vpn-out-na1-nix";
    gatewayHost = networkTopology.lib.fqdn "networking-vpn-out-na1-nix";
    normalGateway = networkTopology.networks.lan.gateway;
    bypassCidrs = [ networkTopology.networks.wgRemote.routedCidr ];
  };
}
