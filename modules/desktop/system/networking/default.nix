{ ... }:
{  
  networking.hostName = "taylor-nix"; # Define your hostname.
  networking.hostId = "34801239";
  networking.networkmanager = {
    enable = true;
  };
}
