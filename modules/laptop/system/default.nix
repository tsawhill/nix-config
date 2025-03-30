{ ... }:{  
  imports = [
  	./boot
    ./nix
    ./hardware
    ./networking
  ];

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;

  # Set time zone and locale
  time.timeZone = "America/Los_Angeles";
  i18n.defaultLocale = "en_US.UTF-8";

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  system.copySystemConfiguration = false;
}
