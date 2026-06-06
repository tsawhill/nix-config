{ lib, networkTopology, ... }:

let
  inherit (networkTopology.lib) lanIp wgAddress;
  wgRemote = networkTopology.networks.wgRemote;
  wgEndpoint = "${wgRemote.endpoint}:${toString wgRemote.port}";
  wgAllowedIPs = "${wgRemote.cidr};${networkTopology.networks.lan.cidr};";
in
{
  networking.networkmanager = {
    enable = true;
  };

  my.secrets.wireguard.pubkeys.enable = true;

  my.network.wg-remote = {
    enable = true;
    address = wgAddress "taylor-laptop-nix";
    autoconnect = "true";
    dns = lanIp networkTopology.networks.lan.dnsHost;
    dnsPriority = -1;
    routeMetric = 50000;
    peer = {
      endpoint = wgEndpoint;
      allowedIPs = wgAllowedIPs;
    };
  };

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  services.blueman.enable = true;
}
