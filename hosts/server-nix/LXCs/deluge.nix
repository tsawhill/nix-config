{
  self,
  lib,
  networkTopology,
  ...
}:
let
  # Leave false until the EU gateway is deployed and verified; see
  # docs/airvpn-eu-deluge.md.
  vpnClientEnabled = false;
in
{
  imports = [
    ./base
    "${self}/modules/network/vpn-egress-client.nix"
    "${self}/modules/software/services/deluge.nix"
  ];

  my.groups.download = {
    enable = true;
    members = [ "root" ];
    gid = 1001;
  };
  networking.hostName = "deluge-nix";
  my.secrets.deluge-vpn.enable = vpnClientEnabled;
  my.services.deluge.portSecret = lib.mkIf vpnClientEnabled "deluge_vpn_port";
  my.network.vpnEgress.client = {
    enable = vpnClientEnabled;
    gatewayAddress = networkTopology.lib.lanIp "networking-vpn-out-eu1-nix";
    normalGateway = networkTopology.networks.lan.gateway;
    bypassCidrs = [ networkTopology.networks.wgRemote.routedCidr ];
  };
}
