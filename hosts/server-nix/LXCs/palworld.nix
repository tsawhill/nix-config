{ self, ... }:
{
  imports = [
    ./base
    "${self}/modules/software/services/palworld.nix"
  ];

  services.palworld = {
    enable = true;
    autoStart = true;

    serverName = "Taylor's Palworld Server";
    serverDescription = "Palworld dedicated server";
    maxPlayers = 16;
  };

  networking.hostName = "palworld-nix";
}
