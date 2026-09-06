{ ... }:
{
  boot.supportedFilesystems = [ "zfs" "ntfs" ];
  networking.hostId = "34801239";
  # Becomes the default at stateVersion 26.11; drop this then.
  boot.zfs.forceImportRoot = false;

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

  # Manual access only: keep every partition unmounted while the Windows VM runs.
  fileSystems."/mnt/windows" = {
    device = "/dev/disk/by-id/nvme-SPCC_M.2_PCIe_SSD_30083920240-part3";
    fsType = "ntfs-3g";
    options = [ "noauto" "ro" "uid=1000" "nofail" ];
  };

  swapDevices = [ ];
}
