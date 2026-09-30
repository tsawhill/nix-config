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

  my.network.router = {
    enable = true;
    # OPNsense's wan0 in instances.yaml
    wanMacAddress = "14:29:0d:71:37:01";
  };

  # Prebuilt so the cutover needs no internet. With the OPNsense VM stopped, run
  # /run/current-system/specialisation/takeover/bin/switch-to-configuration switch
  # Rollback: stop this container, start OPNsense.
  specialisation.takeover.configuration.my.network.router.takeover = true;
}
