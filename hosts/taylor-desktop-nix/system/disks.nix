{ ... }:
{
  boot.supportedFilesystems = [ "zfs" "ntfs" ];
  networking.hostId = "34801239";

  fileSystems."/" = {
    device = "zpool/root";
    fsType = "zfs";
  };

  fileSystems."/nix" = {
    device = "zpool/nix";
    fsType = "zfs";
  };

  fileSystems."/var" = {
    device = "zpool/var";
    fsType = "zfs";
  };

  fileSystems."/home" = {
    device = "zpool/home";
    fsType = "zfs";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/2B70-97D0";
    fsType = "vfat";
    options = [ "fmask=0022" "dmask=0022" ];
  };

  # Windows drive
  fileSystems."/mnt/windows" = {
    device = "/dev/nvme1n1p3";
    fsType = "ntfs-3g";
    options = [ "rw" "uid=1000" "nofail" ];
  };

  swapDevices = [ ];
}
