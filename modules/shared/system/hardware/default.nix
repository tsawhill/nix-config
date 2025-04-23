{
  pkgs,
  ...
}:
{
  # Enable Bluetooth
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
  services.blueman.enable = true;

  # Enable power profile daemon
  services.power-profiles-daemon.enable = true;

  # Enable brother laser printer
  services.printing.drivers = [
    pkgs.brlaser
    pkgs.brgenml1lpr
    pkgs.brgenml1cupswrapper
  ];
}
