{
  imports = [
    ./systemd-boot.nix
  ];
  boot.loader.efi.canTouchEfiVariables = true;
  boot.zfs.devNodes = "/dev/disk/by-partuuid";
}
