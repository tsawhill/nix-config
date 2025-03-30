{ ... }:
{  
  networking.hostName = "taylor-nixlaptop"; # Define your hostname.
  networking.hostId = "33801239";
  networking.networkmanager = {
    enable = true;
  };
}
