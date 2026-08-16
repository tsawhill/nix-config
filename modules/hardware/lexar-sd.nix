# Lexar 1TB SD card, mounted at a stable path on every host that takes it.
#
# Keyed on filesystem UUID rather than a device path so the same card works in
# the cube's USB reader (usb-Generic-_SD_MMC_CRW_...) and the deck's native slot
# (mmc-LX1TB_...), which present completely different device names.
{
  lib,
  config,
  ...
}:

let
  cfg = config.my.lexarSD;
in
{
  options.my.lexarSD = {
    enable = lib.mkEnableOption "Lexar SD card mount";

    mountPoint = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/lexarSD";
      description = "Where the card is mounted.";
    };

    uuid = lib.mkOption {
      type = lib.types.str;
      default = "d9376c23-584c-45f5-bc03-4c461a4704b3";
      description = "Filesystem UUID of the card's partition.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Automount, same as the CIFS shares. autofs covers the mount point from
    # boot, so with the card out a write never reaches the internal disk - it
    # fails with ENODEV once the device wait times out. Without autofs the bare
    # directory would be exposed and anything writing there would silently fill
    # the root filesystem instead.
    fileSystems.${cfg.mountPoint} = {
      device = "/dev/disk/by-uuid/${cfg.uuid}";
      fsType = "ext4";
      options = [
        "nofail" # never block boot when the card is out
        "noatime"
        "x-systemd.automount"
        "x-systemd.device-timeout=5s" # bounds the wait; 90s is the default
      ];
    };
  };
}
