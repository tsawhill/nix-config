{
  ...
}:
{
  # Enable Bluetooth
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
  services.blueman.enable = true;

  # Enable power profile daemon
  services.power-profiles-daemon.enable = true;
}
