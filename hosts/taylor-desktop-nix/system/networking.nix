{ pkgs, lib, ... }:
{
  networking.useDHCP = lib.mkDefault true;
  networking.networkmanager.enable = true;

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = {
      General = {
        Enable = "Source,Sink,Media,Socket";
        Experimental = true;
        FastConnectable = true;
        DiscoverableTimeout = 0;
        # Increase timeouts for slower devices
        PairTimeout = 300;
        DiscardConnectedDevices = true;
      };
    };
  };

  services.blueman.enable = true;
}
