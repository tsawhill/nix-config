{ config, lib, ... }:

let
  cfg = config.my.secrets.searx_secret_key;
in
{
  options.my.secrets.searx_secret_key = {
    enable = lib.mkEnableOption "Searx secret key";
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.searx_secret_key = {
      sopsFile = ./searx_secret_key.yaml;
    };
  };
}
