{ pkgs, config, ... }:
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
      Type = "simple";
      UMask = "007";
      EnvironmentFile = config.sops.secrets.radarr_api_key.path;
      ExecStart = "${pkgs.radarr}/bin/Radarr -nobrowser";
      Restart = "always";
      TimeoutStopSec = "20";
      User = "root";
      Group = "root";
      SupplementaryGroups = "media download";
    };

    wantedBy = [ "multi-user.target" ];
  };

  networking.firewall.allowedTCPPorts = [ 7878 ];
}
