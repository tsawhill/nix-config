{
  imports = [
    ./systemd-boot.nix
  ];
  boot.loader.efi.canTouchEfiVariables = true;
  boot.zfs.devNodes = "/dev/disk/by-partuuid";
  boot.kernelParams = [
    "video=DP-1:2560x1440@359.99899"
    "video=DP-2:3440x1440@120.00000"
    "amdgpu.ppfeaturemask=0xfffd7fff"
  ];
}
