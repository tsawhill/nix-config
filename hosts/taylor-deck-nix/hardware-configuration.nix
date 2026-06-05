{
  config,
  lib,
  modulesPath,
  ...
}:
# Generated on-device by nixos-generate-config (Steam Deck internal NVMe).
# NOTE: nixos-generate-config emitted a duplicate `fileSystems."/boot"` (a real
# vfat entry plus a bogus `none`/bind entry); the bind one was removed here so
# the config evaluates. Everything else is as generated.
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "usbhid"
    "usb_storage"
    "sd_mod"
    "sdhci_pci"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModulePackages = [ ];

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

  swapDevices = [ ];

  hardware.enableRedistributableFirmware = lib.mkDefault true;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
