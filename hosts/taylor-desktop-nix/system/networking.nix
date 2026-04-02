{ pkgs, ... }:
{
  networking.networkmanager.enable = true;

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  services.bluez.enable = true;
  services.bluez.settings = {
    General = {
      Enable = "Source,Sink,Media,Socket";
      Experimental = true;
      FastConnectable = true;
      DiscoverableTimeout = 0;
      ControllerMode = "bredr";
      # Increase timeouts for slower devices
      PairTimeout = 300;
      DiscardConnectedDevices = true;
    };
  };

  services.blueman.enable = true;
}
