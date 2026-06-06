{ lib, networkTopology, ... }:

let
  inherit (networkTopology.lib) lanIp wgAddress;
  wgRemote = networkTopology.networks.wgRemote;
  wgEndpoint = "${wgRemote.endpoint}:${toString wgRemote.port}";
  wgAllowedIPs = "${networkTopology.networks.lan.cidr};${wgRemote.routedCidr};";
in
{
  networking.useDHCP = lib.mkDefault true;
  networking.networkmanager.enable = true;
  networking.firewall.checkReversePath = "loose";

  my.secrets.wireguard.pubkeys.enable = true;

  my.network.wg-remote = {
    enable = true;
    address = wgAddress "pi-backup-nix";
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
