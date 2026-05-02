{ config, pkgs, ... }:

let
  # Source roots to protect. Syncoid receives each source under the same path
  # beneath the Pi's `backup` pool, e.g. `zpool/code` -> `backup/zpool/code`.
  #
  # `rpool` is intentionally split into children. The bare `backup/rpool`
  # dataset is just a container on the target, and trying to replicate the empty
  # parent caused Syncoid to refuse the sync once children already existed.
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

  # Sanoid creates/prunes source snapshots for every configured root and all of
  # its children.
  mkDatasetConfig = dataset: {
    name = dataset;
    value = {
      useTemplate = [ "backup" ];
      recursive = "zfs";
    };
  };

  # Syncoid sends snapshots to the non-root receiver on pi-backup-nix.
  # `recvOptions = "u x mountpoint"` keeps received datasets unmounted and
  # excludes source mountpoint properties, so the backup pool layout stays under
  # the target host's control.
  mkSyncoidCommand = dataset: {
    name = dataset;
    value = {
      target = "syncoid-recv@pi-backup-nix.lan:backup/${dataset}";
      recursive = true;
      recvOptions = "u x mountpoint";
    };
  };

  # Target-side cleanup uses ZFS user properties as grace-period markers.
  # Datasets and snapshots are marked first, then destroyed only after the grace
  # period if the source side still does not contain them.
  orphanProperty = "org.tsawhill:orphaned-since";
  staleSnapshotProperty = "org.tsawhill:stale-snapshot-since";
  orphanGraceDays = 90;
  backupDatasetArgs = builtins.concatStringsSep " " backupDatasets;
in
{
  # Source-side snapshot policy: daily/monthly retention, no hourly/yearly
  # snapshots. The Pi has its own Sanoid config that prunes received snapshots
  # without creating snapshots there.
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

  # Replication runs after Sanoid has had time to create the day's snapshots.
  services.syncoid = {
    enable = true;
    interval = "*-*-* 03:00:00";
    sshKey = config.sops.secrets.server_nix_syncoid_id_ed25519.path;
    commonArgs = [ "--no-sync-snap" ];
    commands = builtins.listToAttrs (map mkSyncoidCommand backupDatasets);
  };

  programs.ssh.knownHosts."pi-backup-nix.lan".publicKey =
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILWyZ/i1VfPZmQphX5HtPsO4DEd0YhHeut7BTTHd8znI";

  # Prune whole target datasets and stale target snapshots that no longer exist
  # on the source. Dataset deletion is recursive but delayed by 90 days; stale
  # snapshots get the same 90-day grace period.
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
      # `ssh -n` matters here: the pruning loops read from temp files, and ssh
      # can otherwise consume stdin and stop the loop after the first remote
      # command.
      ssh_cmd="ssh -n -i ${config.sops.secrets.server_nix_syncoid_id_ed25519.path} -o BatchMode=yes -o IdentitiesOnly=yes"
      orphan_property="${orphanProperty}"
      stale_snapshot_property="${staleSnapshotProperty}"
      grace_days=${toString orphanGraceDays}
      today="$(date -u +%F)"
      cutoff_epoch="$(date -u -d "$grace_days days ago" +%s)"

      expected_file="$(mktemp)"
      expected_snapshot_file="$(mktemp)"
      target_file="$(mktemp)"
      target_snapshot_file="$(mktemp)"
      stale_snapshot_file="$(mktemp)"
      trap 'rm -f "$expected_file" "$expected_snapshot_file" "$target_file" "$target_snapshot_file" "$stale_snapshot_file"' EXIT

      $ssh_cmd "$ssh_remote" true
      $ssh_cmd "$ssh_remote" zfs list -H -o name backup >/dev/null

      # Build four sets:
      # - expected datasets/snapshots from server-nix
      # - actual datasets/snapshots on pi-backup-nix
      # The target lists are fetched with the same key/account Syncoid uses.
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

      # Stale snapshots are target snapshots missing from the source snapshot
      # set. Snapshots under orphaned datasets are skipped here because the
      # dataset orphan pass handles them recursively after its grace period.
      comm -23 "$target_snapshot_file" "$expected_snapshot_file" > "$stale_snapshot_file"

      while IFS= read -r target_snapshot; do
        [ -n "$target_snapshot" ] || continue

        target_dataset="''${target_snapshot%@*}"
        if ! grep -Fxq "$target_dataset" "$expected_file"; then
          echo "Skipping snapshot for orphaned backup dataset $target_snapshot"
          continue
        fi

        echo "Found stale backup snapshot $target_snapshot"
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
      done < "$stale_snapshot_file"

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
