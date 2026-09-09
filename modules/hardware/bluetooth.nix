# Bluetooth stack, plus the experimental BlueZ interface PipeWire needs to
# report device battery levels over HFP.
{ lib, config, ... }:
{
  options.my.hardware.bluetooth.enable = lib.mkEnableOption "Bluetooth with blueman" // {
    default = true;
  };

  config = lib.mkIf config.my.hardware.bluetooth.enable {
    hardware.bluetooth = {
      enable = true;
      powerOnBoot = true;
      # Gates org.bluez.BatteryProviderManager1; without it Battery1 never appears.
      settings.General.Experimental = true;
    };

    services.blueman.enable = true;
  };
}
