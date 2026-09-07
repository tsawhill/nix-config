{ config, pkgs, lib, ... }:
let
  # Follow the newest versioned kernel supported by our configured ZFS package.
  zfsCompatibleKernelPackages = lib.filterAttrs (
    name: kernelPackages:
    builtins.match "linux_[0-9]+_[0-9]+" name != null
    && (
      let
        zfsCheck = builtins.tryEval (
          kernelPackages.${config.boot.zfs.package.kernelModuleAttribute}.meta.broken
        );
      in
      zfsCheck.success && !zfsCheck.value
    )
  ) pkgs.linuxKernel.packages;
  sortedKernelPackages = lib.sort (a: b: lib.versionOlder a.kernel.version b.kernel.version) (
    builtins.attrValues zfsCompatibleKernelPackages
  );
in
{
  boot.kernelPackages =
    if sortedKernelPackages == [ ] then
      throw "No ZFS-compatible kernel found for taylor-desktop-nix"
    else
      lib.last sortedKernelPackages;

  boot.loader.efi.canTouchEfiVariables = true;
  boot.zfs.devNodes = "/dev/disk/by-partuuid";

  boot.loader.systemd-boot = {
    enable = true;
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
