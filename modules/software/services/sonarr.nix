{ pkgs, ... }:
{
  environment.systemPackages = [ pkgs.sonarr ];

  systemd.services.sonarr = {
    enable = true;
    path = [ pkgs.sonarr ];

    unitConfig = {
      Description = "Sonarr systemd service";
      Documentation = "man:Sonarr";
      After = "network-online.target";
    };

    serviceConfig = {
      type = "simple";
      UMask = "002";
      ExecStart = "/usr/bin/env Sonarr -nobrowser";
      Restart = "on-failure";
      TimeoutStopSec = "20";
      User = "root";
      Group = "root";
      SupplementaryGroups = "media download";
    };

    wantedBy = [ "multi-user.target" ];
  };

  networking.firewall.allowedTCPPorts = [ 8989 ];
}
