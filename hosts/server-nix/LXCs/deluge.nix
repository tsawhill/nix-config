{
  self,
  lib,
  networkTopology,
  ...
}:
let
  settings = import ./vpn-eu-settings.nix;
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
  assertions = [
    {
      assertion = !settings.delugeEnable || settings.gatewayEnable;
      message = "Enable and verify the EU gateway before routing Deluge through it.";
    }
  ];
  my.secrets.deluge-vpn.enable = settings.delugeEnable;
  my.services.deluge.portSecret = lib.mkIf settings.delugeEnable "deluge_vpn_port";
  my.network.vpnEgress.client = {
    enable = settings.delugeEnable;
    gatewayAddress = networkTopology.lib.lanIp "networking-vpn-out-eu1-nix";
    normalGateway = networkTopology.networks.lan.gateway;
    bypassCidrs = [ networkTopology.networks.wgRemote.routedCidr ];
  };
}
