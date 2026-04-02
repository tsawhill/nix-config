{ pkgs, config, ... }:
{
  environment.systemPackages = [ pkgs.prowlarr ];

  systemd.services.prowlarr = {
    enable = true;
    path = [ pkgs.prowlarr ];

    unitConfig = {
      Description = "Prowlarr systemd service";
      Documentation = "man:Prowlarr";
      After = "network-online.target";
    };

    serviceConfig = {
      Type = "simple";
      UMask = "007";
      EnvironmentFile = config.sops.secrets.prowlarr_api_key.path;
      ExecStart = "${pkgs.prowlarr}/bin/Prowlarr -nobrowser";
      Restart = "always";
      TimeoutStopSec = "20";
      User = "root";
      Group = "root";
    };

    wantedBy = [ "multi-user.target" ];
  };

  networking.firewall.allowedTCPPorts = [ 9696 ];
}
