{ config, ... }:

let
  backupDatasets = [
    "VM-Disks"
    "downloadHDD/nix-stores"
    "downloadSSD"
    "rpool"
    "zpool/immich"
    "zpool/nextcloud"
    "zpool/code"
    "zpool/taylor"
  ];

  mkDatasetConfig = dataset: {
    name = dataset;
    value = {
      useTemplate = [ "backup" ];
      recursive = "zfs";
    };
  };

  mkSyncoidCommand = dataset: {
    name = dataset;
    value = {
      target = "syncoid-recv@pi-backup-nix.lan:backup/${dataset}";
      recursive = true;
      recvOptions = "u x mountpoint";
    };
  };
in
{
  services.sanoid = {
    enable = true;
    interval = "*-*-* 01:00:00";
    templates.backup = {
      autosnap = true;
      autoprune = true;
      hourly = 0;
      daily = 30;
      monthly = 12;
      yearly = 0;
    };
    datasets = builtins.listToAttrs (map mkDatasetConfig backupDatasets);
  };

  services.syncoid = {
    enable = true;
    interval = "*-*-* 03:00:00";
    sshKey = config.sops.secrets.syncoid_pi_backup_id_ed25519.path;
    commonArgs = [ "--no-sync-snap" ];
    commands = builtins.listToAttrs (map mkSyncoidCommand backupDatasets);
  };

  programs.ssh.knownHosts."pi-backup-nix.lan".publicKey =
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILWyZ/i1VfPZmQphX5HtPsO4DEd0YhHeut7BTTHd8znI";
}
