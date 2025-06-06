{ pkgs, ... }:
{
  networking.hostName = "taylor-deck"; # Define your hostname.
  networking.hostId = "34801249";
  networking.networkmanager = {
    enable = true;
    dispatcherScripts = [
      {
        source = ./scripts/wifi-toggle.sh;
        type = "basic";
      }
    ];
  };
  systemd.services.NetworkManager-dispatcher = {
    enable = true;
    path = [
      pkgs.networkmanager
    ];
  };

}
