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

    extraSettings = {
      # minutes between supply drops (default 180)
      SupplyDropSpan = "30";
    };
  };

  networking.hostName = "palworld-nix";
}
