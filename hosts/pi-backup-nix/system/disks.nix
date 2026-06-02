{
  config,
  lib,
  pkgs,
  ...
}:

let
  zfs = config.boot.zfs.package;
  # Backup pool drives — spin down after 5 min idle.
  backupDriveIds = [
    "Hitachi_HUA723030ALA640_MK0371YHK6P13A"
    "WDC_WD30EZRZ-00WN9B0_WD-WCC4E7KF51NR"
    "Hitachi_HUA723030ALA640_MK0371YHJZLJ0A"
  ];
  hdIdleArgs = lib.concatMapStringsSep " " (id: "-a /dev/disk/by-id/ata-${id} -i 300") backupDriveIds;
in
{
  systemd.services.hd-idle = {
    description = "Spin down backup pool drives after idle";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.hd-idle}/bin/hd-idle -i 0 ${hdIdleArgs}";
    };
  };

  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.extraPools = [ "backup" ];
  boot.zfs.devNodes = "/dev/disk/by-id";

  networking.hostId = "8425e349";

  # Keep the backup pool mounted at the host-local mountpoint without forcing a
  # remount during every activation. `zfs set -u` updates the property without
  # unmounting `/mnt/backup`, which avoids deploy failures while the pool is in
  # use.
  systemd.services.configure-zfs-datasets = {
    description = "Ensure ZFS datasets have correct mountpoints";
    wantedBy = [ "zfs.target" ];
    after = [ "zfs-import.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      if [ "$(${zfs}/bin/zfs get -H -o value mountpoint backup)" != "/mnt/backup" ]; then
        ${zfs}/bin/zfs set -u mountpoint=/mnt/backup backup
      fi
    '';
  };

  fileSystems."/mnt/backup" = {
    device = "backup";
    fsType = "zfs";
    options = [
      "nofail"
    ];
  };
}
