{ self, ... }:
{
  imports = [ "${self}/modules/hardware/zfs-latest-kernel.nix" ];

  my.boot.zfsLatestKernel.enable = true;

  boot.loader.efi.canTouchEfiVariables = true;
  boot.zfs.devNodes = "/dev/disk/by-partuuid";

  # TODO: move to my.boot.limine once Windows' ESP partition GUID can be read for its entry.
  boot.loader.systemd-boot = {
    enable = true;
    # Full-resolution text mode, so entry titles (and their build dates) fit.
    consoleMode = "max";
    edk2-uefi-shell.enable = true;
    windows."10" = {
      efiDeviceHandle = "HD1b";
      title = "Windows 10";
    };
  };

  boot.kernelParams = [
    "amd_pstate=active"
    "iommu=pt"
  ];

  boot.initrd.availableKernelModules = [
    "nvme"
    "thunderbolt"
    "xhci_pci"
    "ahci"
    "usbhid"
    "usb_storage"
    "sd_mod"
  ];

  boot.kernelModules = [ "kvm-amd" ];

  boot.kernel.sysctl."kernel.sysrq" = 1;

  # Force reboot if shutdown hangs (CIFS/ZFS unmount can stall with dead network)
  systemd.settings.Manager = {
    RebootWatchdogSec = "2min";
    DefaultTimeoutStopSec = "30s";
  };

}
