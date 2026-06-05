{ ... }:
{
  # Steam Deck boots UEFI; jovian.devices.steamdeck.enable handles the APU,
  # firmware, kernel modules, controls, fan and backlight. Filesystem/partition
  # details come from the device-generated hardware-configuration.nix.
  boot.loader.systemd-boot = {
    enable = true;
    configurationLimit = 10;
  };
  boot.loader.efi.canTouchEfiVariables = true;
}
