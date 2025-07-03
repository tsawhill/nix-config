{
  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot = {
    enable = true;
    configurationLimit = 6;
    edk2-uefi-shell.enable = true;
    windows = {
      "10" = {
        efiDeviceHandle = "HD1b";
        title = "Windows 10";
      };
    };
  };
}
