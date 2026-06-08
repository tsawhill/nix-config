{ self, ... }:
{
  imports = [
    ./base
  ];

  my.monitoring.metrics.stack.enable = true;
  networking.hostName = "monitoring-nix";
}
