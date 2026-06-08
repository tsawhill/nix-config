{ ... }:
{
  # Steam Deck boots UEFI; jovian.devices.steamdeck.enable handles the APU,
  # firmware, kernel modules, controls, fan and backlight.
  boot.loader.systemd-boot = {
    enable = true;
    configurationLimit = 10;
  };
  boot.loader.efi.canTouchEfiVariables = true;

  # Storage controllers needed in the initrd to reach the root filesystem.
  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "usbhid"
    "usb_storage"
    "sd_mod"
    "sdhci_pci"
  ];
}
