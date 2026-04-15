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
  boot.extraModprobeConfig = "options snd-usb-audio lowlatency=y";

  # Disable USB autosuspend for PreSonus Studio 24c to prevent audio crackling
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="194f", ATTR{idProduct}=="0109", ATTR{power/control}="on"
  '';

  boot.kernel.sysctl."kernel.sysrq" = 1;

  # Force reboot if shutdown hangs (CIFS/ZFS unmount can stall with dead network)
  systemd.settings.Manager = {
    RebootWatchdogSec = "2min";
    DefaultTimeoutStopSec = "30s";
  };

  boot.kernelPackages =
    let
      # Take the latest stock kernel that supports ZFS, then enable PREEMPT_RT
      rtKernel = latestKernelPackage.kernel.override {
        structuredExtraConfig = with lib.kernel; {
          PREEMPT_RT = yes;
          PREEMPT_VOLUNTARY = lib.mkForce no;
          PREEMPT = lib.mkForce no;
        };
      };
    in
    pkgs.linuxPackagesFor rtKernel;
}
