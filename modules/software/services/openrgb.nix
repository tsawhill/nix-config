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

    # Disable the system service — it runs sandboxed and can't access HID devices.
    # OpenRGB is managed as a user-level systemd service instead.
    systemd.services.openrgb.wantedBy = lib.mkForce [ ];

    services.udev.packages = [ pkgs.openrgb-with-all-plugins ];
    services.udev.extraRules = ''
      # OpenRGB uses libusb for many controllers and needs RW access to /dev/bus/usb/*
      SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", GROUP="plugdev", MODE="0660"
    '';

    # i2c is required for most RGB controllers
    hardware.i2c.enable = true;
    boot.kernelModules = [
      "i2c-dev"
      smBusModule
    ];

    # AMD BIOS reserves SMBus resources via ACPI; this allows i2c-piix4 to access them
    boot.kernelParams = lib.mkIf (cfg.cpuVendor == "amd") [ "acpi_enforce_resources=lax" ];

    environment.systemPackages = [ pkgs.openrgb-with-all-plugins ];

    users.groups.plugdev = { };
    users.users = lib.genAttrs cfg.users (_: {
      extraGroups = [ "plugdev" ];
    });
  };
}
