{ pkgs, ... }:

{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # This script runs every time you switch configurations
  boot.loader.systemd-boot.extraInstallCommands = ''
    LOG_FILE="/var/log/efi-sync.log"
    echo "--- NixOS Rebuild EFI Sync: $(date) ---" >> $LOG_FILE


    # 1. Ensure the fallback is mounted
    if ! ${pkgs.util-linux}/bin/mountpoint -q /boot-fallback; then
      echo "Attempting to mount /boot-fallback..." >> $LOG_FILE
      ${pkgs.util-linux}/bin/mount /boot-fallback >> $LOG_FILE 2>&1 || echo "CRITICAL: Fallback drive mount failed!" >> $LOG_FILE
    fi

    # 2. Sync if both exist
    if ${pkgs.util-linux}/bin/mountpoint -q /boot && ${pkgs.util-linux}/bin/mountpoint -q /boot-fallback; then
       echo "Syncing EFI partitions..." >> $LOG_FILE
       # Using -rtv instead of -a to avoid FAT32 permission errors
       ${pkgs.rsync}/bin/rsync -rtv --delete /boot/ /boot-fallback/ >> $LOG_FILE 2>&1
       echo "Sync complete." >> $LOG_FILE
    else
       echo "ERROR: Skipping sync. One or both mountpoints are missing." >> $LOG_FILE
    fi
  '';
  # EMERGENCY FAILOVER: If /boot is empty/missing, this link lets
  # NixOS tools find the kernels on the other drive.
  systemd.services.fix-boot-path = {
    description = "Fix /boot if primary drive failed";
    wantedBy = [ "multi-user.target" ];
    script = ''
      if ! /run/current-system/sw/bin/mountpoint -q /boot; then
        echo "/boot is missing, linking to /boot-fallback"
        ln -snf /boot-fallback /boot
      fi
    '';
    serviceConfig.Type = "oneshot";
  };
}
