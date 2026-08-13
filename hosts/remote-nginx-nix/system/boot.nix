{
  boot.loader.grub = {
    efiSupport = true;
    efiInstallAsRemovable = true;
    device = "nodev";

    # Keep kernels and initrds on the root filesystem.  OCI's 105 MiB ESP is
    # mounted at /boot/efi and only holds the removable GRUB EFI executable.
    copyKernels = false;
    configurationLimit = 5;
  };

  boot.loader.efi = {
    canTouchEfiVariables = false;
    efiSysMountPoint = "/boot/efi";
  };
}
