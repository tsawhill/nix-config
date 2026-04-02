{ ... }:
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
    "video=DP-1:2560x1440@360,rgb_range=full"
    "video=DP-2:3440x1440@165,rgb_range=full"
    "amdgpu.mes=0"
    "amdgpu.gpu_recovery=1"
    "amdgpu.lockup_timeout=1000,1000,1000,1000"
  ];

  boot.kernel.sysctl."kernel.sysrq" = 1;
}
