{ self, ... }:
{
  imports = [
    ./base
  ];

  my.monitoring.metrics.stack.enable = true;
  my.secrets.grafana_secret_key.enable = true;
  networking.hostName = "monitoring-nix";
}
