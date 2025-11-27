{
  imports = [
    ./systemd-boot.nix
  ];
  boot.loader.efi.canTouchEfiVariables = true;
  boot.zfs.devNodes = "/dev/disk/by-partuuid";
  boot.kernelParams = [
    "video=DP-1:2560x1440@360"
    "video=DP-2:3440x1440@165"
    "amdgpu.ppfeaturemask=0xfff73fff"
  ];
}
