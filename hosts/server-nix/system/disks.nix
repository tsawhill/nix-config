{ pkgs, ... }:
{
  # Enable ZFS support
  boot.supportedFilesystems = [ "zfs" ];
  # Set a unique Host ID (Required for ZFS)
  networking.hostId = "42526202";

  systemd.services.configure-zfs-datasets = {
    description = "Ensure ZFS datasets have correct mountpoints";
    wantedBy = [ "zfs.target" ];
    after = [ "zfs-import.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      ${pkgs.zfs}/bin/zfs set mountpoint=/mnt/nix-stores downloadHDD/nix-stores
      ${pkgs.zfs}/bin/zfs set mountpoint=/mnt/zpool zpool
      ${pkgs.zfs}/bin/zfs set mountpoint=/mnt/downloadHDD downloadHDD
      ${pkgs.zfs}/bin/zfs set mountpoint=/mnt/downloadSSD downloadSSD
    '';
  };
  boot.zfs.forceImportRoot = true; # Import root even if booting from the mirrored boot drive.

  boot.kernelParams = [
    # Limit ZFS dirty data to 512MB (prevents massive I/O spikes)
    "zfs.zfs_dirty_data_max=536870912"

    # Start flushing to disk sooner (at 64MB) to keep I/O consistent
    "zfs.zfs_dirty_data_sync_percent=10"

    # Cap ZFS ARC at 16GB (out of 64GB) — prevents ZFS from consuming
    # all free RAM at the expense of LXC workloads
    "zfs.zfs_arc_max=17179869184"
  ];

  fileSystems = {
    "/" = {
      device = "rpool/root";
      fsType = "zfs";
    };

    "/home" = {
      device = "rpool/home";
      fsType = "zfs";
    };

    "/boot" = {
      device = "/dev/disk/by-uuid/4F32-30CA";
      fsType = "vfat";
      options = [
        "fmask=0077"
        "dmask=0077"
        "nofail"
      ];
    };

    "/boot-fallback" = {
      device = "/dev/disk/by-uuid/4FA1-BC07";
      fsType = "vfat";
      options = [
        "fmask=0077"
        "dmask=0077"
        "nofail"
      ];
    };

    "/mnt/nix-stores" = {
      device = "downloadHDD/nix-stores";
      fsType = "zfs";
      options = [
        "nofail"
      ]; # Still boot if the zpool is not available.
    };

    "/mnt/zpool" = {
      device = "zpool";
      fsType = "zfs";
      options = [
        "nofail"
      ]; # Still boot if the zpool is not available.
    };

    "/mnt/downloadHDD" = {
      device = "downloadHDD";
      fsType = "zfs";
      options = [
        "nofail"
      ]; # Still boot if the zpool is not available.
    };

    "/mnt/downloadSSD" = {
      device = "downloadSSD";
      fsType = "zfs";
      options = [
        "nofail"
      ]; # Still boot if the zpool is not available.
    };

    "/mnt/gameSSD" = {
      device = "/dev/sdc1";
      fsType = "ext4";
      options = [
        "nofail"
      ];
    };
  };
  swapDevices = [
    {
      device = "/dev/disk/by-id/nvme-CT500P310SSD8_25044DA9B89F-part3";
      randomEncryption.enable = true;
    }
    {
      device = "/dev/disk/by-id/nvme-CT500P310SSD8_25044DA9B9F2-part3";
      randomEncryption.enable = true;
    }
  ];
}
