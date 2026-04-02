# Udev to allow hid access for Mchose web driver
{ lib, config, ... }:
{
  options.my.udev.mchosem7.enable = lib.mkEnableOption "hidraw access for Mchose M7 peripherals" // {
    default = true;
  };

  config = lib.mkIf config.my.udev.mchosem7.enable {
    services.udev.extraRules = ''
      KERNEL=="hidraw*", ATTRS{idVendor}=="5253", ATTRS{idProduct}=="0031", MODE="0664", GROUP="input"
      KERNEL=="hidraw*", ATTRS{idVendor}=="5253", ATTRS{idProduct}=="1020", MODE="0664", GROUP="input"
    '';
  };
}
