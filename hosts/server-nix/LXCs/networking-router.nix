{
  self,
  ...
}:

{
  imports = [
    ./base
    "${self}/modules/network/router.nix"
  ];

  networking.hostName = "networking-router-nix";

  my.network.router.enable = true;

  # Prebuilt so the cutover needs no internet. With the OPNsense VM stopped, run
  # /run/current-system/specialisation/takeover/bin/switch-to-configuration switch
  # Rollback: stop this container, start OPNsense.
  specialisation.takeover.configuration.my.network.router.takeover = true;
}
