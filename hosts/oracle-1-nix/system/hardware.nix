{ modulesPath, ... }:
{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  boot.tmp.cleanOnBoot = true;

  # A1.Flex has 6 GB and no swap partition (disko lays out ESP + root only).
  # zram covers build/renewal spikes without eating boot-volume space.
  zramSwap.enable = true;

  # OCI attaches the boot volume paravirtualised, so the guest sees virtio-scsi.
  boot.initrd.availableKernelModules = [
    "virtio_pci"
    "virtio_scsi"
    "virtio_blk"
    "usbhid"
    "sr_mod"
  ];

  # Disko owns the partition table: nixos-anywhere wipes /dev/sda and recreates
  # it from this. Do not add `fileSystems` entries by hand, they come from here.
  disko.devices.disk.main = {
    device = "/dev/sda";
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          priority = 1;
          size = "512M";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };
}
