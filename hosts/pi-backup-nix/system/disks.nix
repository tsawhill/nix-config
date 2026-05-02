{ pkgs, ... }:

{
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
      if [ "$(${pkgs.zfs}/bin/zfs get -H -o value mountpoint backup)" != "/mnt/backup" ]; then
        ${pkgs.zfs}/bin/zfs set -u mountpoint=/mnt/backup backup
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
