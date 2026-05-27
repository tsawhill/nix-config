{ lib, ... }:
{
  networking.useDHCP = lib.mkDefault true;
  networking.networkmanager.enable = true;
  networking.interfaces.eno2.wakeOnLan.enable = true;

  my.network.wg-remote = {
    enable = true;
    address = "10.50.50.2/32";
    autoconnect = "true";
    dns = "10.73.73.6";
    dnsPriority = -1;
    routeMetric = 50000;
    peer = {
      publicKey = "***REDACTED_WG_PUBKEY***";
      endpoint = "taylordnsfree.zapto.org:51820";
      allowedIPs = "10.50.50.0/24;10.73.73.0/24;";
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
