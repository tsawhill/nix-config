{ pkgs, ... }:
{
  networking.hostName = "taylor-nix"; # Define your hostname.
  networking.hostId = "34801239";
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
