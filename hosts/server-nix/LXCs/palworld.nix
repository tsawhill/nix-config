{ config, self, ... }:
{
  imports = [
    ./base
    "${self}/modules/software/services/palworld.nix"
  ];

  my.secrets.palworld_env.enable = true;

  services.palworld = {
    enable = true;
    autoStart = true;
    autoUpdate.enable = true;
    environmentFile = config.sops.secrets.palworld_env.path;

    serverName = "THE DOJO";
    serverDescription = "hehehe fnuny pokemon :)";
    maxPlayers = 16;
  };

  networking.hostName = "palworld-nix";
}
