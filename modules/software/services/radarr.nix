{ pkgs, ... }:
{
  environment.systemPackages = [ pkgs.radarr ];

  systemd.services.radarr = {
    enable = true;
    path = [ pkgs.radarr ];

    unitConfig = {
      Description = "Radarr systemd service";
      Documentation = "man:radarr";
      After = "network-online.target";
    };

    serviceConfig = {
      type = "simple";
      UMask = "007";
      ExecStart = "/usr/bin/env Radarr -nobrowser";
      Restart = "on-failure";
      TimeoutStopSec = "20";
      User = "root";
      Group = "root";
      SupplementaryGroups = "media download";
    };

    wantedBy = [ "multi-user.target" ];
  };

  networking.firewall.allowedTCPPorts = [ 7878 ];
}
