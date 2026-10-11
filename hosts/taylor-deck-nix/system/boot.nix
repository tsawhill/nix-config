{ ... }:
{
  # Steam Deck boots UEFI; jovian.devices.steamdeck.enable handles the APU,
  # firmware, kernel modules, controls, fan and backlight.
  my.boot.limine = {
    enable = true;
    # 1280x800 panel
    fontScale = "1x1";
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
