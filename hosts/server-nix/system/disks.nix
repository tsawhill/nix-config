{
  # Enable ZFS support
  boot.supportedFilesystems = [ "zfs" ];
  # Set a unique Host ID (Required for ZFS)
  networking.hostId = "42526202";

  boot.kernelParams = [
    # Limit ZFS dirty data to 512MB (prevents massive I/O spikes)
    "zfs.zfs_dirty_data_max=536870912"

    # Start flushing to disk sooner (at 64MB) to keep I/O consistent
    "zfs.zfs_dirty_data_sync_percent=10"
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
      ];
    };

    "/mnt/zpool" = {
      device = "zpool";
      fsType = "zfs";
      options = [
        "nofail"
      ]; # Still boot if the zpool is not available.
    };

    "/mnt/zpool/documents" = {
      device = "zpool/documents";
      fsType = "zfs";
      options = [
        "nofail"
      ];
    };

    "/mnt/zpool/gamesaves" = {
      device = "zpool/gamesaves";
      fsType = "zfs";
      options = [
        "nofail"
      ];
    };

    "/mnt/zpool/gameservers" = {
      device = "zpool/gameservers";
      fsType = "zfs";
      options = [
        "nofail"
      ];
    };

    "/mnt/zpool/immich" = {
      device = "zpool/immich";
      fsType = "zfs";
      options = [
        "nofail"
      ];
    };

    "/mnt/zpool/media" = {
      device = "zpool/media";
      fsType = "zfs";
      options = [
        "nofail"
      ];
    };

    "/mnt/zpool/nextcloud" = {
      device = "zpool/nextcloud";
      fsType = "zfs";
      options = [
        "nofail"
      ];
    };

    "/mnt/zpool/nixosconfigs" = {
      device = "zpool/nixosconfigs";
      fsType = "zfs";
      options = [
        "nofail"
      ];
    };

    "/mnt/zpool/nixoslxcconfigs" = {
      device = "zpool/nixoslxcconfigs";
      fsType = "zfs";
      options = [
        "nofail"
      ];
    };

    "/mnt/zpool/roms" = {
      device = "zpool/roms";
      fsType = "zfs";
      options = [
        "nofail"
      ];
    };

    "/mnt/zpool/shadowplay" = {
      device = "zpool/shadowplay";
      fsType = "zfs";
      options = [
        "nofail"
      ];
    };

    "/mnt/downloadHDD" = {
      device = "downloadHDD";
      fsType = "zfs";
      options = [
        "nofail"
      ];
    };

    "/mnt/downloadSSD" = {
      device = "downloadSSD";
      fsType = "zfs";
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
