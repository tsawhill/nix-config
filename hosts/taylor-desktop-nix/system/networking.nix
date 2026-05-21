{ lib, ... }:
{
  networking.useDHCP = lib.mkDefault true;
  networking.networkmanager.enable = true;

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
