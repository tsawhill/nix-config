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
  options.my.openrgb = {
    cpuVendor = lib.mkOption {
      type = lib.types.enum [
        "amd"
        "intel"
      ];
      default = "amd";
      description = "CPU vendor, used to select the correct SMBus kernel module for OpenRGB.";
    };

    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "taylor" ];
      description = "Users to add to the plugdev group for USB RGB device access.";
    };
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

    # AMD BIOS reserves SMBus resources via ACPI; this allows i2c-piix4 to access them
    boot.kernelParams = lib.mkIf (cfg.cpuVendor == "amd") [ "acpi_enforce_resources=lax" ];

    environment.systemPackages = [ pkgs.openrgb-with-all-plugins ];

    users.users = lib.genAttrs cfg.users (_: { extraGroups = [ "plugdev" ]; });
  };
}
