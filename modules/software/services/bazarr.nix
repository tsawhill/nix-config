{ pkgs, ... }:
{

  systemd.services.bazarr = {
    enable = true;
    path = [ pkgs.bazarr ];

    unitConfig = {
      Description = "Bazarr systemd service";
      Documentation = "man:bazarr";
      After = "network-online.target";
    };

    serviceConfig = {
      type = "simple";
      UMask = "007";
      ExecStart = "/usr/bin/env bazarr -c /root/.config/bazarr/data";
      Restart = "on-failure";
      TimeoutStopSec = "20";
      User = "root";
      Group = "root";
      SupplementaryGroups = "media download";
    };

    wantedBy = [ "multi-user.target" ];
  };

  networking.firewall.allowedTCPPorts = [ 6767 ];
}
