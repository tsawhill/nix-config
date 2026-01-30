{ modulesPath, ... }:
{
  boot.tmp.cleanOnBoot = true;
  zramSwap.enable = true;
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];
  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/C701-80FD";
    fsType = "vfat";
  };
  boot.initrd.availableKernelModules = [
    "ata_piix"
    "uhci_hcd"
    "xen_blkfront"
    "vmw_pvscsi"
  ];
  boot.initrd.kernelModules = [ "nvme" ];
  fileSystems."/" = {
    device = "/dev/sda1";
    fsType = "ext4";
  };

}
