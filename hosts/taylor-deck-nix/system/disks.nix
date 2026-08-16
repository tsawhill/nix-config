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

  # The 1TB Lexar SD card is mounted at /mnt/lexarSD by modules/hardware/lexar-sd.nix,
  # keyed on filesystem UUID so it resolves in this slot and in the cube's USB reader.

  swapDevices = [ ];
}
