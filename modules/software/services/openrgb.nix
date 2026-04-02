{ pkgs, ... }:
{
  services.hardware.openrgb = {
    enable = true;
    package = pkgs.openrgb-with-all-plugins;
  };

  services.udev.packages = [ pkgs.openrgb-with-all-plugins ];

  # i2c is required for most RGB controllers
  hardware.i2c.enable = true;
  boot.kernelModules = [ "i2c-dev" ];

  environment.systemPackages = [ pkgs.openrgb-with-all-plugins ];
}
