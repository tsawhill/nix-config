{ pkgs, ... }:
{
  systemd.services.deluged = {
    enable = true;
    path = [ pkgs.deluged ];

    unitConfig = {
      Description = "Deluge Bittorrent Client Daemon";
      Documentation = "man:deluged";
      After = "network-online.target";
    };

    serviceConfig = {
      type = "simple";
      UMask = "007";
      ExecStart = "${pkgs.deluged}/bin/deluged -d";
      Restart = "on-failure";
      TimeoutStopSec = "300";
      User = "root";
      Group = "root";
      SupplementaryGroups = "download";
    };

    wantedBy = [ "multi-user.target" ];
  };

  systemd.services.deluge-web = {
    enable = true;

    unitConfig = {
      Description = "Deluge Bittorrent Client Web UI";
      Documentation = "man:deluge-web";
      After = "deluged.service";
      Wants = "deluged.service";
    };

    serviceConfig = {
      type = "simple";
      UMask = "027";
      ExecStart = "${pkgs.deluged}/bin/deluge-web -d";
      Restart = "on-failure";
      User = "root";
      Group = "root";
      SupplementaryGroups = "download";
    };

    wantedBy = [ "multi-user.target" ];
  };
  networking.firewall.allowedTCPPorts = [
    8112
    58846
    47096
  ];
  networking.firewall.allowedUDPPorts = [
    58846
    47096
  ];

}
