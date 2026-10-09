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
    # The Incus tier pools are created under these parents.
    before = [ "incus-declarative-apply.service" ];
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

      ensure_dataset() {
        name="$1"
        shift
        ${pkgs.zfs}/bin/zfs list -H "$name" >/dev/null 2>&1 \
          || ${pkgs.zfs}/bin/zfs create "$@" "$name"
      }

      # LXC tier parents (incus/registry.nix tiers); Incus creates <zpool>/lxc/incus.
      # Nothing under them is mounted on the host.
      ensure_dataset rpool/lxc -o canmount=off -o mountpoint=none -o compression=zstd -o atime=off
      if ${pkgs.zfs}/bin/zfs list -H scratchSSD >/dev/null 2>&1; then
        ensure_dataset scratchSSD/lxc -o canmount=off -o mountpoint=none -o atime=off
      fi

      # nixos-factory's /nix template moved here from inside the old rpool Incus pool.
      if ${pkgs.zfs}/bin/zfs list -H rpool/VMDisks/nix-templates >/dev/null 2>&1 \
        && ! ${pkgs.zfs}/bin/zfs list -H rpool/lxc/templates >/dev/null 2>&1
      then
        ${pkgs.zfs}/bin/zfs rename rpool/VMDisks/nix-templates rpool/lxc/templates
      fi

      # Never-mounted receive side for zfs-backups.nix, mirroring source paths; a
      # mounted copy could be written to and break the next incremental receive.
      ensure_dataset zpool/backups -o canmount=off -o mountpoint=none
      for parent in rpool rpool/lxc rpool/lxc/incus scratchSSD scratchSSD/lxc scratchSSD/lxc/incus; do
        ensure_dataset "zpool/backups/$parent" -o canmount=off
      done
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
