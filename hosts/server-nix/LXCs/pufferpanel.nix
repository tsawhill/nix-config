{ self, ... }:
{
  imports = [
    ./base
    "${self}/modules/software/services/pufferpanel.nix"
  ];

  # Open ports for the servers
  networking.firewall.allowedTCPPorts = [
    25565 # Minecraft
  ];
  networking.firewall.allowedUDPPorts = [
    25565 # Minecraft
  ];

  networking.hostName = "pufferpanel-nix";
}
