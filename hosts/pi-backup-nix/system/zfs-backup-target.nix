{ pkgs, ... }:

{
  environment.systemPackages = [
    pkgs.sanoid
    pkgs.zfs
  ];

  users.groups.syncoid-recv = { };
  users.users.syncoid-recv = {
    isSystemUser = true;
    group = "syncoid-recv";
    home = "/var/lib/syncoid-recv";
    createHome = true;
    shell = pkgs.bashInteractive;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILzjP3mVlVL+E3xxvbE9HT/H47sRxej+fcArYVlo2tV6 syncoid@server-nix-to-pi-backup"
    ];
  };

  systemd.services.prepare-zfs-backup-pool = {
    description = "Prepare backup pool for Syncoid receives";
    wantedBy = [ "zfs.target" ];
    after = [ "zfs-import.target" ];
    serviceConfig.Type = "oneshot";
    path = [
      pkgs.coreutils
      pkgs.zfs
    ];
    script = ''
      if zfs list backup >/dev/null 2>&1; then
        for dataset in backup/VM-Disks backup/downloadHDD backup/downloadSSD backup/rpool backup/zpool; do
          if zfs list "$dataset" >/dev/null 2>&1; then
            zfs set -u mountpoint=none "$dataset"
          else
            zfs create -o mountpoint=none "$dataset"
          fi
        done

        for dataset in backup backup/VM-Disks backup/downloadHDD backup/downloadSSD backup/rpool backup/zpool; do
          zfs allow -u syncoid-recv change-key,compression,create,destroy,mount,mountpoint,receive,rollback,userprop "$dataset"
        done
      fi
    '';
  };

  services.zfs.autoScrub = {
    enable = true;
    interval = "monthly";
    pools = [ "backup" ];
  };

  services.sanoid = {
    enable = true;
    interval = "*-*-* 04:00:00";
    templates.backup-target = {
      autosnap = false;
      autoprune = true;
      hourly = 0;
      daily = 30;
      monthly = 12;
      yearly = 0;
    };
    datasets."backup" = {
      useTemplate = [ "backup-target" ];
      recursive = "zfs";
      processChildrenOnly = true;
    };
  };
}
