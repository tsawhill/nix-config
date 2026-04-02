{ pkgs, config, ... }:
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
      Type = "simple";
      UMask = "007";
      EnvironmentFile = config.sops.secrets.sonarr_api_key.path;
      ExecStart = "${pkgs.sonarr}/bin/Sonarr -nobrowser";
      Restart = "always";
      TimeoutStopSec = "20";
      User = "root";
      Group = "root";
      SupplementaryGroups = "media download";
    };

    wantedBy = [ "multi-user.target" ];
  };

  networking.firewall.allowedTCPPorts = [ 8989 ];
}
