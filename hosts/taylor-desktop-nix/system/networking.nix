{ lib, networkTopology, ... }:

let
  inherit (networkTopology.lib) lanIp wgAddress;
  wgRemote = networkTopology.networks.wgRemote;
  wgEndpoint = "${wgRemote.endpoint}:${toString wgRemote.port}";
  wgAllowedIPs = "${wgRemote.cidr};${networkTopology.networks.lan.cidr};";
in
{
  networking.useDHCP = lib.mkDefault true;
  networking.networkmanager.enable = true;
  networking.interfaces.eno2.wakeOnLan.enable = true;

  my.secrets.wireguard.pubkeys.enable = true;

  my.network.wg-remote = {
    enable = true;
    address = wgAddress "taylor-desktop-nix";
    autoconnect = "true";
    dns = lanIp networkTopology.networks.lan.dnsHost;
    dnsPriority = -1;
    routeMetric = 50000;
    peer = {
      endpoint = wgEndpoint;
      allowedIPs = wgAllowedIPs;
    };
  };

  my.network.airvpn = {
    enable = true;
    address = "10.150.209.24/32";
    cities = [
      "SanJose-California"
      "Fremont-California"
    ];
    autoconnect = "Bunda";
  };

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = {
      General = {
        Experimental = true;
        FastConnectable = true;
        DiscoverableTimeout = 0;
      };
    };
  };

  services.blueman.enable = true;
}
