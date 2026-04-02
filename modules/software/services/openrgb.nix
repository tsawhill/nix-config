{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.my.openrgb;
  smBusModule = if cfg.cpuVendor == "intel" then "i2c-i801" else "i2c-piix4";
in
{
  options.my.openrgb.cpuVendor = lib.mkOption {
    type = lib.types.enum [
      "amd"
      "intel"
    ];
    default = "amd";
    description = "CPU vendor, used to select the correct SMBus kernel module for OpenRGB.";
  };

  config = {
    services.hardware.openrgb = {
      enable = true;
      package = pkgs.openrgb-with-all-plugins;
    };

    services.udev.packages = [ pkgs.openrgb-with-all-plugins ];

    # i2c is required for most RGB controllers
    hardware.i2c.enable = true;
    boot.kernelModules = [
      "i2c-dev"
      smBusModule
    ];

    environment.systemPackages = [ pkgs.openrgb-with-all-plugins ];
  };
}
