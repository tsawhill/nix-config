{ pkgs, lib, ... }:
let
  # Use the latest ZFS-compatible kernel
  zfsCompatibleKernelPackages = lib.filterAttrs (
    name: kernelPackages:
    let
      zfsCheck = builtins.tryEval kernelPackages.${pkgs.zfs_unstable.kernelModuleAttribute}.meta.broken;
    in
    (builtins.match "linux_[0-9]+_[0-9]+" name) != null && zfsCheck.success && (!zfsCheck.value)
  ) pkgs.linuxKernel.packages;
  latestKernelPackage = lib.last (
    lib.sort (a: b: lib.versionOlder a.kernel.version b.kernel.version) (
      builtins.attrValues zfsCompatibleKernelPackages
    )
  );
in
{
  boot.loader.efi.canTouchEfiVariables = true;
  boot.zfs.devNodes = "/dev/disk/by-partuuid";

  boot.loader.systemd-boot = {
    enable = true;
    configurationLimit = 6;
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

  boot.kernelPackages = latestKernelPackage;

  # TODO: Remove once btmtk fix lands in stable kernel (NixOS/nixpkgs#521528)
  boot.kernelPatches = [
    {
      name = "bluetooth-btmtk-accept-short-wmt-func-ctrl";
      patch = pkgs.fetchurl {
        url = "https://git.kernel.org/pub/scm/linux/kernel/git/bluetooth/bluetooth-next.git/patch/?id=162b1adeb057d28ad84fd8a03f3c50cf08db5c62";
        hash = "sha256-ij0hQmC0U++AdXWQy6nycnDe6z4yaMoQIrSiLal5DHc=";
      };
    }
  ];
}
