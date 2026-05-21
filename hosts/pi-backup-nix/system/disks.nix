{ lib, pkgs, ... }:

let
  hdparm = lib.getExe pkgs.hdparm;
in
{
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.extraPools = [ "backup" ];
  boot.zfs.devNodes = "/dev/disk/by-id";

  networking.hostId = "8425e349";

  # The backup pool is normally idle outside the nightly receive/prune window.
  # Set the three pool disks to enter standby after 30 minutes of device idle
  # time. hdparm encodes 30 minutes as `-S 241`.
  services.udev.extraRules = ''
    ACTION=="add|change", SUBSYSTEM=="block", ENV{DEVTYPE}=="disk", ENV{ID_SERIAL}=="Hitachi_HUA723030ALA640_MK0371YHK6P13A", RUN+="${hdparm} -S 241 /dev/%k"
    ACTION=="add|change", SUBSYSTEM=="block", ENV{DEVTYPE}=="disk", ENV{ID_SERIAL}=="WDC_WD30EZRZ-00WN9B0_WD-WCC4E7KF51NR", RUN+="${hdparm} -S 241 /dev/%k"
    ACTION=="add|change", SUBSYSTEM=="block", ENV{DEVTYPE}=="disk", ENV{ID_SERIAL}=="Hitachi_HUA723030ALA640_MK0371YHJZLJ0A", RUN+="${hdparm} -S 241 /dev/%k"
  '';

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
