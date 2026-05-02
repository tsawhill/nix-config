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
  staleSnapshotProperty = "org.tsawhill:stale-snapshot-since";
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

      ssh_remote="syncoid-recv@pi-backup-nix.lan"
      ssh_cmd="ssh -i ${config.sops.secrets.syncoid_pi_backup_id_ed25519.path} -o BatchMode=yes -o IdentitiesOnly=yes"
      orphan_property="${orphanProperty}"
      stale_snapshot_property="${staleSnapshotProperty}"
      grace_days=${toString orphanGraceDays}
      today="$(date -u +%F)"
      cutoff_epoch="$(date -u -d "$grace_days days ago" +%s)"

      expected_file="$(mktemp)"
      expected_snapshot_file="$(mktemp)"
      target_file="$(mktemp)"
      target_snapshot_file="$(mktemp)"
      trap 'rm -f "$expected_file" "$expected_snapshot_file" "$target_file" "$target_snapshot_file"' EXIT

      $ssh_cmd "$ssh_remote" true
      $ssh_cmd "$ssh_remote" zfs list -H -o name backup >/dev/null

      for source_root in ${backupDatasetArgs}; do
        target_root="backup/$source_root"

        if zfs list -H -o name "$source_root" >/dev/null 2>&1; then
          zfs list -H -o name -r "$source_root" \
            | sed 's#^#backup/#' >> "$expected_file"
          zfs list -H -t snapshot -o name -r "$source_root" 2>/dev/null \
            | sed 's#^#backup/#' >> "$expected_snapshot_file" || true
        fi

        if $ssh_cmd "$ssh_remote" zfs list -H -o name "$target_root" >/dev/null 2>&1; then
          $ssh_cmd "$ssh_remote" zfs list -H -o name -r "$target_root" >> "$target_file"
          $ssh_cmd "$ssh_remote" zfs list -H -t snapshot -o name -r "$target_root" >> "$target_snapshot_file"
        fi
      done

      sort -u -o "$expected_file" "$expected_file"
      sort -u -o "$expected_snapshot_file" "$expected_snapshot_file"
      sort -ur -o "$target_file" "$target_file"
      sort -u -o "$target_snapshot_file" "$target_snapshot_file"

      echo "Expected backup datasets: $(wc -l < "$expected_file")"
      echo "Expected backup snapshots: $(wc -l < "$expected_snapshot_file")"
      echo "Target backup datasets: $(wc -l < "$target_file")"
      echo "Target backup snapshots: $(wc -l < "$target_snapshot_file")"

      while IFS= read -r target_snapshot; do
        [ -n "$target_snapshot" ] || continue

        target_dataset="''${target_snapshot%@*}"
        if ! grep -Fxq "$target_dataset" "$expected_file"; then
          continue
        fi

        if grep -Fxq "$target_snapshot" "$expected_snapshot_file"; then
          if [ "$($ssh_cmd "$ssh_remote" zfs get -H -o value "$stale_snapshot_property" "$target_snapshot" 2>/dev/null || true)" != "-" ]; then
            echo "Clearing stale snapshot marker on $target_snapshot"
            $ssh_cmd "$ssh_remote" zfs inherit "$stale_snapshot_property" "$target_snapshot"
          fi
          continue
        fi

        stale_since="$($ssh_cmd "$ssh_remote" zfs get -H -o value "$stale_snapshot_property" "$target_snapshot" 2>/dev/null || true)"
        if [ -z "$stale_since" ] || [ "$stale_since" = "-" ]; then
          echo "Marking stale backup snapshot $target_snapshot"
          $ssh_cmd "$ssh_remote" zfs set "$stale_snapshot_property=$today" "$target_snapshot"
          continue
        fi

        stale_epoch="$(date -u -d "$stale_since" +%s 2>/dev/null || echo 0)"
        if [ "$stale_epoch" -le "$cutoff_epoch" ]; then
          echo "Destroying stale backup snapshot $target_snapshot marked since $stale_since"
          $ssh_cmd "$ssh_remote" zfs destroy "$target_snapshot"
        else
          echo "Keeping stale backup snapshot $target_snapshot marked since $stale_since"
        fi
      done < "$target_snapshot_file"

      while IFS= read -r target_dataset; do
        [ -n "$target_dataset" ] || continue

        if grep -Fxq "$target_dataset" "$expected_file"; then
          if [ "$($ssh_cmd "$ssh_remote" zfs get -H -o value "$orphan_property" "$target_dataset" 2>/dev/null || true)" != "-" ]; then
            echo "Clearing orphan marker on $target_dataset"
            $ssh_cmd "$ssh_remote" zfs inherit "$orphan_property" "$target_dataset"
          fi
          continue
        fi

        orphaned_since="$($ssh_cmd "$ssh_remote" zfs get -H -o value "$orphan_property" "$target_dataset" 2>/dev/null || true)"
        if [ -z "$orphaned_since" ] || [ "$orphaned_since" = "-" ]; then
          echo "Marking orphaned backup dataset $target_dataset"
          $ssh_cmd "$ssh_remote" zfs set "$orphan_property=$today" "$target_dataset"
          continue
        fi

        orphan_epoch="$(date -u -d "$orphaned_since" +%s 2>/dev/null || echo 0)"
        if [ "$orphan_epoch" -le "$cutoff_epoch" ]; then
          echo "Destroying orphaned backup dataset $target_dataset marked since $orphaned_since"
          $ssh_cmd "$ssh_remote" zfs destroy -r "$target_dataset"
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
