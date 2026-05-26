{ config, lib, ... }:

let
  cfg = config.my.secrets.gotify_token_deploy;
in
{
  options.my.secrets.gotify_token_deploy = {
    enable = lib.mkEnableOption "Gotify token secret for deploy notifications";
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.gotify_token_deploy = {
      sopsFile = ./gotify_token_deploy.yaml;
    };
  };
}
