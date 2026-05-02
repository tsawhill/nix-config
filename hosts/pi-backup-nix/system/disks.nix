{ pkgs, ... }:

{
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.extraPools = [ "backup" ];
  boot.zfs.devNodes = "/dev/disk/by-id";

  networking.hostId = "8425e349";

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
