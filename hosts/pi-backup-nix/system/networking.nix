{ lib, ... }:
{
  networking.useDHCP = lib.mkDefault true;
  networking.networkmanager.enable = true;
  networking.firewall.checkReversePath = "loose";

  my.secrets.wireguard.pubkeys.enable = true;

  my.network.wg-remote = {
    enable = true;
    address = "10.50.50.5/32";
    autoconnect = "true";
    dns = "10.73.73.6";
    dnsPriority = 50;
    routeMetric = 50000;
    peer = {
      endpoint = "taylordnsfree.zapto.org:51820";
      allowedIPs = "10.73.73.0/24;10.50.0.0/16;";
    };
  };
}
