{ config, lib, ... }:

let
  cfg = config.my.secrets.grafana_secret_key;
in
{
  options.my.secrets.grafana_secret_key = {
    enable = lib.mkEnableOption "Grafana secret key";
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.grafana_secret_key = {
      sopsFile = ./grafana_secret_key.yaml;
      owner = "grafana";
      group = "grafana";
      mode = "0400";
    };
  };
}
