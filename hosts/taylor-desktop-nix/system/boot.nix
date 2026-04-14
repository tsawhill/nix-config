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
    "usbcore.autosuspend=-1"
    "processor.max_cstate=1"
    # "video=DP-1:2560x1440@360,rgb_range=full"
    # "video=DP-2:3440x1440@165,rgb_range=full"
    # "amdgpu.mes=0"
    # "amdgpu.gpu_recovery=1"
    # "amdgpu.lockup_timeout=1000,1000,1000,1000"
    # "amdgpu.gfxoff=0"
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

  boot.kernelPackages =
    let
      zenZfsCheck = builtins.tryEval pkgs.linuxPackages_zen.${pkgs.zfs_unstable.kernelModuleAttribute}.meta.broken;
    in
    if zenZfsCheck.success && (!zenZfsCheck.value)
    then pkgs.linuxPackages_zen
    else latestKernelPackage;
  boot.zfs.package = pkgs.zfs_unstable;
}
