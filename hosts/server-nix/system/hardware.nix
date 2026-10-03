{ config, ... }:
{
  # Use schedutil governor: scales CPU frequency with load,
  # reducing idle power without hurting burst performance.
  powerManagement.cpuFreqGovernor = "schedutil";

  # r8169 wants rtl_nic/rtl8125b-2.fw, and the kernel asks for Zenbleed microcode.
  hardware.enableRedistributableFirmware = true;
  hardware.cpu.amd.updateMicrocode = config.hardware.enableRedistributableFirmware;
}
