{ lib, config, ... }:
{
  hardware.enableRedistributableFirmware = lib.mkDefault true;
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  # AMD virtualization (KVM).
  boot.kernelModules = [ "kvm-amd" ];
}
