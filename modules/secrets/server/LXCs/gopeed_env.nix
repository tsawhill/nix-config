{ config, lib, ... }:

let
  cfg = config.my.secrets.gopeed_env;
in
{
  options.my.secrets.gopeed_env = {
    enable = lib.mkEnableOption "Gopeed web UI password and API token";
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.gopeed_env = {
      sopsFile = ./gopeed_env.yaml;
      restartUnits = [ "gopeed.service" ];
    };
  };
}
