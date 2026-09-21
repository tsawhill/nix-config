{ config, pkgs, ... }:
{
  environment.systemPackages = [ pkgs.openssl ];

  systemd.services.jellyfin = {
    enable = true;
    path = [
      pkgs.jellyfin
      pkgs.jellyfin-web
      pkgs.jellyfin-ffmpeg
    ];

    unitConfig = {
      Description = "Jellyfin Media Server";
      Documentation = "man:jellyfin";
      After = "network-online.target";
    };

    # Keep logs (incl. FFmpeg transcode logs) outside /root so the log agent can read them.
    environment.JELLYFIN_LOG_DIR = "/var/log/jellyfin";

    serviceConfig = {
      type = "simple";
      LogsDirectory = "jellyfin";
      ExecStart = "/usr/bin/env jellyfin";
      Restart = "always";
      TimeoutStopSec = "20";
      User = "root";
      Group = "root";
      SupplementaryGroups = "media";
    };

    wantedBy = [ "multi-user.target" ];
  };

  networking.firewall.allowedTCPPorts = [
    443
    8096
  ];
}
