{
  lib,
  networkTopology,
  pkgs,
  ...
}:
let
  incusRegistry = import ./incus/registry.nix { inherit lib networkTopology; };
  inherit (incusRegistry) appData;
in
{
  # Enable ZFS support
  boot.supportedFilesystems = [ "zfs" ];
  # Set a unique Host ID (Required for ZFS)
  networking.hostId = "42526202";

  systemd.services.configure-zfs-datasets = {
    description = "Ensure ZFS datasets have correct mountpoints";
    wantedBy = [ "zfs.target" ];
    after = [ "zfs-import.target" ];
    # Guests' /appdata sources must exist before Incus starts or hot-adds them.
    before = [
      "incus.service"
      "incus-declarative-apply.service"
    ];
    serviceConfig.Type = "oneshot";
    script = ''
      # Setting a property remounts the dataset, which Incus bind mounts block.
      set_property() {
        [ "$(${pkgs.zfs}/bin/zfs get -H -o value "$1" "$3")" = "$2" ] \
          || ${pkgs.zfs}/bin/zfs set "$1=$2" "$3"
      }

      set_property mountpoint /mnt/nix-stores downloadHDD/nix-stores
      set_property mountpoint /mnt/zpool zpool
      set_property mountpoint /mnt/downloadHDD downloadHDD
      set_property mountpoint /mnt/downloadSSD downloadSSD
      set_property mountpoint /mnt/scratchSSD scratchSSD

      set_property atime off downloadHDD/nix-stores

      # Mirrored-NVMe tier of guest /nix stores (see incus/registry.nix nixStores).
      ${pkgs.zfs}/bin/zfs list -H rpool/nix-stores >/dev/null 2>&1 \
        || ${pkgs.zfs}/bin/zfs create -o mountpoint=/mnt/rpool/nix-stores \
          -o compression=zstd -o atime=off rpool/nix-stores

      # Never-mounted receive side for zfs-backups.nix's appdata replication.
      ${pkgs.zfs}/bin/zfs list -H zpool/backups >/dev/null 2>&1 \
        || ${pkgs.zfs}/bin/zfs create -o canmount=off -o mountpoint=none zpool/backups
      ${pkgs.zfs}/bin/zfs list -H zpool/backups/appdata >/dev/null 2>&1 \
        || ${pkgs.zfs}/bin/zfs create -o canmount=off zpool/backups/appdata

      # One app data dataset per declared guest (see incus/registry.nix appData),
      # owned by container root (idmap base 100000).
      if ${pkgs.zfs}/bin/zfs list -H scratchSSD >/dev/null 2>&1; then
        ${pkgs.zfs}/bin/zfs list -H ${appData.dataset} >/dev/null 2>&1 \
          || ${pkgs.zfs}/bin/zfs create -o atime=off ${appData.dataset}
        for guest in ${lib.escapeShellArgs (lib.attrNames incusRegistry.instances)}; do
          if ! ${pkgs.zfs}/bin/zfs list -H "${appData.dataset}/$guest" >/dev/null 2>&1; then
            ${pkgs.zfs}/bin/zfs create "${appData.dataset}/$guest"
            chown 100000:100000 "${appData.mount}/$guest"
          fi
        done
      fi
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
      ];
    };

    "/mnt/zpool" = {
      device = "zpool";
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

    "/mnt/scratchSSD" = {
      device = "scratchSSD";
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
