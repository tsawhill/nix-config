{ config, pkgs, ... }:

let
  backupDatasets = [
    "VM-Disks"
    "downloadHDD/nix-stores"
    "downloadSSD"
    "rpool/VMDisks"
    "rpool/home"
    "rpool/root"
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

  orphanProperty = "org.tsawhill:orphaned-since";
  orphanGraceDays = 90;
  backupDatasetArgs = builtins.concatStringsSep " " backupDatasets;
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

  systemd.services.prune-zfs-backup-orphans = {
    description = "Mark and prune orphaned ZFS backup datasets";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig.Type = "oneshot";
    path = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
      pkgs.openssh
      pkgs.zfs
    ];
    script = ''
      set -euo pipefail

      remote="root@pi-backup-nix.lan"
      orphan_property="${orphanProperty}"
      grace_days=${toString orphanGraceDays}
      today="$(date -u +%F)"
      cutoff_epoch="$(date -u -d "$grace_days days ago" +%s)"

      expected_file="$(mktemp)"
      target_file="$(mktemp)"
      trap 'rm -f "$expected_file" "$target_file"' EXIT

      for source_root in ${backupDatasetArgs}; do
        target_root="backup/$source_root"

        if zfs list -H -o name "$source_root" >/dev/null 2>&1; then
          zfs list -H -o name -r "$source_root" \
            | sed 's#^#backup/#' >> "$expected_file"
        fi

        ssh "$remote" zfs list -H -o name -r "$target_root" 2>/dev/null >> "$target_file" || true
      done

      sort -u -o "$expected_file" "$expected_file"
      sort -ur -o "$target_file" "$target_file"

      while IFS= read -r target_dataset; do
        [ -n "$target_dataset" ] || continue

        if grep -Fxq "$target_dataset" "$expected_file"; then
          if [ "$(ssh "$remote" zfs get -H -o value "$orphan_property" "$target_dataset" 2>/dev/null || true)" != "-" ]; then
            echo "Clearing orphan marker on $target_dataset"
            ssh "$remote" zfs inherit "$orphan_property" "$target_dataset"
          fi
          continue
        fi

        orphaned_since="$(ssh "$remote" zfs get -H -o value "$orphan_property" "$target_dataset" 2>/dev/null || true)"
        if [ -z "$orphaned_since" ] || [ "$orphaned_since" = "-" ]; then
          echo "Marking orphaned backup dataset $target_dataset"
          ssh "$remote" zfs set "$orphan_property=$today" "$target_dataset"
          continue
        fi

        orphan_epoch="$(date -u -d "$orphaned_since" +%s 2>/dev/null || echo 0)"
        if [ "$orphan_epoch" -le "$cutoff_epoch" ]; then
          echo "Destroying orphaned backup dataset $target_dataset marked since $orphaned_since"
          ssh "$remote" zfs destroy -r "$target_dataset"
        else
          echo "Keeping orphaned backup dataset $target_dataset marked since $orphaned_since"
        fi
      done < "$target_file"
    '';
  };

  systemd.timers.prune-zfs-backup-orphans = {
    description = "Run orphaned ZFS backup dataset pruning";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 05:00:00";
      Persistent = true;
      Unit = "prune-zfs-backup-orphans.service";
    };
  };
}
