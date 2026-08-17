{ config, lib, ... }:

let
  cfg = config.my.secrets.grafana_admin_password;
in
{
  options.my.secrets.grafana_admin_password = {
    enable = lib.mkEnableOption "Grafana admin password";
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.grafana_admin_password = {
      sopsFile = ./grafana_admin_password.yaml;
      owner = "grafana";
      group = "grafana";
      mode = "0400";
    };
  };
}
