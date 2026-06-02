{ lib, ... }:
{
  networking.networkmanager = {
    enable = true;
  };

  my.secrets.wireguard.pubkeys.enable = true;

  my.network.wg-remote = {
    enable = true;
    address = "10.50.50.3/32";
    autoconnect = "true";
    dns = "10.73.73.6";
    dnsPriority = -1;
    routeMetric = 50000;
    peer = {
      endpoint = "taylordnsfree.zapto.org:51820";
      allowedIPs = "10.50.50.0/24;10.73.73.0/24;";
    };
  };

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  services.blueman.enable = true;
}
