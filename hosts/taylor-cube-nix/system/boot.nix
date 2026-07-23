{ ... }:
{
  boot.loader.systemd-boot = {
    enable = true;
    configurationLimit = 10;
  };
  boot.loader.efi.canTouchEfiVariables = true;

  # RetroCultMods "MiniHost" GH Guitar adapter (VID:PID 1209:2882) intermittently
  # self-resets/disconnects on this xHCI-only box. Disable USB Link Power
  # Management for just that device (quirk "k" = USB_QUIRK_NO_LPM) — a common fix
  # for devices that drop off xHCI. Scoped to the one VID:PID, fully reversible.
  boot.kernelParams = [ "usbcore.quirks=1209:2882:k" ];

  # Storage controllers needed in the initrd to reach the root filesystem
  # (from nixos-generate-config on this machine).
  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "usbhid"
    "usb_storage"
    "sd_mod"
  ];
}
