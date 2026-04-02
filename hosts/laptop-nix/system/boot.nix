{ pkgs, ... }:

{
  hardware.enableRedistributableFirmware = true;
  hardware.cpu.amd.updateMicrocode = true;

  boot.initrd.availableKernelModules = [ "nvme" "thunderbolt" "xhci_pci" "ahci" "usbhid" "usb_storage" "sd_mod" ];
  boot.kernelModules = [ "kvm-amd" ];

  boot.loader.efi.canTouchEfiVariables = true;
  boot.zfs.devNodes = "/dev/disk/by-partuuid";

  boot.loader.systemd-boot = {
    enable = true;
    configurationLimit = 6;
  };
}
