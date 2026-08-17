{ self, ... }:
{
  imports = [
    ./base
  ];

  my.monitoring.metrics.stack.enable = true;
  my.secrets.grafana_secret_key.enable = true;
  my.secrets.grafana_admin_password.enable = true;
  networking.hostName = "monitoring-nix";
}
