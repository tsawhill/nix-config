{ pkgs, ... }: {
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
      type = "simple";
      UMask = "007";
      ExecStart = "/usr/bin/env Prowlarr -nobrowser";
      Restart = "on-failure";
      TimeoutStopSec = "20";
      User = "root";
      Group = "root";
    };

    wantedBy = [ "multi-user.target" ];
  };

  networking.firewall.allowedTCPPorts = [ 9696 ];
}
