{ pkgs, ... }:

{
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.extraPools = [ "backup" ];
  boot.zfs.devNodes = "/dev/disk/by-id";

  networking.hostId = "8425e349";

  systemd.services.configure-zfs-datasets = {
    description = "Ensure ZFS datasets have correct mountpoints";
    wantedBy = [ "zfs-mount.service" ];
    after = [ "zfs-import.target" ];
    before = [ "zfs-mount.service" ];
    serviceConfig.Type = "oneshot";
    script = ''
      ${pkgs.zfs}/bin/zfs set mountpoint=/mnt/backup backup
    '';
  };
}
