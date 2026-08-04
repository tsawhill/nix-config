{ networkTopology, ... }:

let
  inherit (networkTopology.lib) lanIp wgAddress;
  wgRemote = networkTopology.networks.wgRemote;
  wgEndpoint = "${wgRemote.endpoint}:${toString wgRemote.port}";
  wgAllowedIPs = "${networkTopology.networks.lan.cidr};${wgRemote.routedCidr};";
in
{
  imports = [ ./networking-base.nix ];

  my.secrets.wireguard.pubkeys.enable = true;
  my.secrets.wireguard.oracle-1-nix.wg-remote.enable = true;

  # This tunnel is load-bearing, not optional: every proxy upstream is a
  # `*.lan` name (see modules/software/services/nginx/proxies), so nginx cannot
  # even resolve its backends until wg-remote is up and LAN DNS is reachable.
  my.network.wg-remote = {
    enable = true;
    address = wgAddress "oracle-1-nix";
    autoconnect = "true";
    dns = lanIp networkTopology.networks.lan.dnsHost;
    dnsPriority = 50;
    routeMetric = 50000;
    peer = {
      endpoint = wgEndpoint;
      allowedIPs = wgAllowedIPs;
    };
  };
}
