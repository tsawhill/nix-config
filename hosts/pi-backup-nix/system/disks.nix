{ pkgs, ... }:

{
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.extraPools = [ "backup" ];
  boot.zfs.devNodes = "/dev/disk/by-id";

  networking.hostId = "70696261";

  systemd.services.configure-zfs-datasets = {
    description = "Ensure ZFS datasets have correct mountpoints";
    wantedBy = [ "zfs.target" ];
    after = [ "zfs-import.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      ${pkgs.zfs}/bin/zfs set mountpoint=/mnt/backup backup
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
