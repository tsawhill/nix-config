{ pkgs, ... }:
{
  networking.firewall.allowedTCPPorts = [ 80 ];

  systemd.services.gotify = {
    enable = true;

    unitConfig = {
      Description = "Gotify systemd service";
      Documentation = "man:gotify-server";
      After = "network-online.target";
    };

    serviceConfig = {
      WorkingDirectory = "/var/lib/gotify-server";
      type = "simple";
      UMask = "007";
      ExecStart = "${pkgs.gotify-server}/bin/server";
      Restart = "on-failure";
      TimeoutStopSec = "20";
      User = "root";
      Group = "root";
    };

    wantedBy = [ "multi-user.target" ];
  };
}
