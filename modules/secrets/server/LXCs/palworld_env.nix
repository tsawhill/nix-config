{ config, lib, ... }:

let
  cfg = config.my.secrets.palworld_env;
in
{
  options.my.secrets.palworld_env = {
    enable = lib.mkEnableOption "Palworld server password environment file";
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.palworld_env = {
      sopsFile = ./palworld_env.yaml;
      owner = "palworld";
      group = "palworld";
      mode = "0400";
      restartUnits = [ "palworld.service" ];
    };
  };
}
