{ pkgs, config, ... }:
{

  systemd.services.lidarr = {
    enable = true;
    path = [ pkgs.lidarr ];

    unitConfig = {
      Description = "Lidarr systemd service";
      Documentation = "man:Lidarr";
      After = "network-online.target";
    };

    serviceConfig = {
      Type = "simple";
      UMask = "007";
      EnvironmentFile = config.sops.secrets.lidarr_api_key.path;
      ExecStart = "${pkgs.lidarr}/bin/Lidarr -nobrowser";
      Restart = "on-failure";
      TimeoutStopSec = "20";
      User = "root";
      Group = "root";
      SupplementaryGroups = "media download";
    };

    wantedBy = [ "multi-user.target" ];
  };

  networking.firewall.allowedTCPPorts = [ 8686 ];
}
