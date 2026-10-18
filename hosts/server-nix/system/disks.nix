{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Group that keeps write access to each shared dataset; appdata/* is single-service.
  sharedDatasets = {
    "zpool/media" = "media";
    "zpool/games/roms" = "games";
    "zpool/games/saves" = "games";
    "zpool/taylor/clips" = "documents";
    "zpool/taylor/documents" = "documents";
    "zpool/taylor/work" = "documents";
    "zpool/taylor/code/nix-config" = "code";
    downloadHDD = "download";
    downloadSSD = "download";
  };

  # Default ACLs miss cp -p/tar/rsync -a modes; run without --root-only to repair a tree.
  sharedDatasetPerms = pkgs.writeShellApplication {
    name = "shared-dataset-perms";
    runtimeInputs = [
      config.boot.zfs.package
      pkgs.acl
      pkgs.coreutils
      pkgs.findutils
    ];
    text = ''
      # Usage: shared-dataset-perms [--root-only] [dataset...]  (default: all)
      declare -A groups=(${
        lib.concatStrings (lib.mapAttrsToList (ds: group: " [${ds}]=${group}") sharedDatasets)
      } )
      root_only=false
      if [ "''${1:-}" = --root-only ]; then
        root_only=true
        shift
      fi
      targets=("$@")
      [ "''${#targets[@]}" -gt 0 ] || targets=("''${!groups[@]}")

      for ds in "''${targets[@]}"; do
        group=''${groups[$ds]:?"$ds is not in sharedDatasets"}
        if [ "$(zfs get -H -o value mounted "$ds" 2>/dev/null)" != yes ]; then
          echo "skipping $ds: not mounted" >&2
          continue
        fi
        [ "$(zfs get -H -o value acltype "$ds")" = posix ] || zfs set acltype=posix "$ds"
        dir=$(zfs get -H -o value mountpoint "$ds")
        acl="d:u::rwx,d:g::rwx,d:g:$group:rwx,d:m::rwx,d:o::rx"

        if $root_only; then
          chgrp "$group" "$dir"
          chmod g+rwxs "$dir"
          setfacl -m "$acl" "$dir"
        else
          echo "$ds ($dir) -> $group"
          chgrp -R "$group" "$dir"
          chmod -R g+rwX "$dir"
          find "$dir" -type d -exec chmod g+s {} + -exec setfacl -m "$acl" {} +
        fi
      done
    '';
  };

  # The JBOD's HBA brings its disks up one by one, ~4.5 s apart, so the last one
  # appears ~55 s into boot: right at the end of NixOS's ~60 s import wait. Wait
  # (up to 3 min) for the whole pool first so it never imports degraded or not at all.
  waitForPool = pool: ''
    zpool=${config.boot.zfs.package}/bin/zpool
    for _ in $(seq 1 180); do
      if "$zpool" list -H ${pool} >/dev/null 2>&1; then
        exit 0
      fi
      state=$("$zpool" import -d ${config.boot.zfs.devNodes} 2>/dev/null \
        | ${pkgs.gawk}/bin/awk -v p=${pool} '$1 == "pool:" { found = ($2 == p) } found && $1 == "state:" { print $2; exit }')
      if [ "$state" = ONLINE ]; then
        exit 0
      fi
      sleep 1
    done
    echo "${pool} not ONLINE after 3 minutes; trying the import anyway" >&2
  '';
in
{
  # Enable ZFS support
  boot.supportedFilesystems = [ "zfs" ];
  # Set a unique Host ID (Required for ZFS)
  networking.hostId = "42526202";

  # The JBOD pools; rpool is on the boot NVMe and imports in the initrd. Never
  # restart an import on switch: the pool's mounts depend on it and go down with it.
  systemd.services.zfs-import-zpool = {
    preStart = waitForPool "zpool";
    restartIfChanged = false;
  };
  systemd.services.zfs-import-downloadHDD = {
    preStart = waitForPool "downloadHDD";
    restartIfChanged = false;
  };
  systemd.services.zfs-import-downloadSSD = {
    preStart = waitForPool "downloadSSD";
    restartIfChanged = false;
  };
  systemd.services.zfs-import-scratchSSD = {
    preStart = waitForPool "scratchSSD";
    restartIfChanged = false;
  };

  environment.systemPackages = [ sharedDatasetPerms ];

  systemd.services.configure-zfs-datasets = {
    description = "Ensure ZFS dataset mountpoints and shared-dataset ACLs";
    wantedBy = [ "zfs.target" ];
    # zfs-mount: the shared-dataset ACLs go on mounted dataset roots.
    after = [
      "zfs-import.target"
      "zfs-mount.service"
    ];
    # The Incus tier pools are created under these parents.
    before = [ "incus-declarative-apply.service" ];
    serviceConfig.Type = "oneshot";
    script = ''
      # Setting a property remounts the dataset, which Incus bind mounts block.
      set_property() {
        [ "$(${pkgs.zfs}/bin/zfs get -H -o value "$1" "$3")" = "$2" ] \
          || ${pkgs.zfs}/bin/zfs set "$1=$2" "$3"
      }

      set_property mountpoint /mnt/zpool zpool
      set_property mountpoint /mnt/downloadHDD downloadHDD
      set_property mountpoint /mnt/downloadSSD downloadSSD
      set_property mountpoint /mnt/scratchSSD scratchSSD

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

      # Never-mounted receive side for zfs-backups.nix, mirroring source paths; a
      # mounted copy could be written to and break the next incremental receive.
      ensure_dataset zpool/backups -o canmount=off -o mountpoint=none
      for parent in rpool rpool/lxc rpool/lxc/incus scratchSSD scratchSSD/lxc scratchSSD/lxc/incus; do
        ensure_dataset "zpool/backups/$parent" -o canmount=off
      done

      ${lib.getExe sharedDatasetPerms} --root-only
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

    # zfsutil: these mountpoints are ZFS properties, which plain mount(8) refuses.
    "/mnt/zpool" = {
      device = "zpool";
      fsType = "zfs";
      options = [
        "nofail"
        "zfsutil"
      ];
    };

    "/mnt/downloadHDD" = {
      device = "downloadHDD";
      fsType = "zfs";
      options = [
        "nofail"
        "zfsutil"
      ];
    };

    "/mnt/downloadSSD" = {
      device = "downloadSSD";
      fsType = "zfs";
      options = [
        "nofail"
        "zfsutil"
      ];
    };

    "/mnt/scratchSSD" = {
      device = "scratchSSD";
      fsType = "zfs";
      options = [
        "nofail"
        "zfsutil"
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
