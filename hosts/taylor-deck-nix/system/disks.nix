{ ... }:
{
  fileSystems."/" = {
    device = "/dev/disk/by-uuid/b9ac0acd-e3b4-44ea-89c1-a26c1cc6ba8f";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/9CCD-DF57";
    fsType = "vfat";
    options = [
      "fmask=0022"
      "dmask=0022"
    ];
  };

  # 1TB SD card. fsType is "auto" (kernel detects the on-disk Linux fs at mount);
  # pin it with `lsblk -f /dev/mmcblk0p1` if you want it explicit. nofail keeps
  # the deck booting when the card is removed.
  fileSystems."/mnt/SDcard" = {
    device = "/dev/disk/by-id/mmc-LX1TB_0x378801e2-part1";
    fsType = "auto";
    options = [
      "nofail"
      "x-systemd.device-timeout=5s"
    ];
  };

  swapDevices = [ ];
}
