{
  # OCI's UEFI firmware does not reliably persist boot entries written via
  # efivars, so install GRUB to the removable path (/EFI/BOOT/BOOTAA64.EFI).
  # This is the same combination that worked on the old x86 OCI proxy.
  boot.loader.grub = {
    efiSupport = true;
    efiInstallAsRemovable = true;
    device = "nodev";
  };

  # Required alongside efiInstallAsRemovable.
  boot.loader.efi.canTouchEfiVariables = false;
}
