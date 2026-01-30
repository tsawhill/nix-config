{ pkgs, ... }:
{
  networking.firewall.allowedTCPPorts = [ 8000 ];
  networking.firewall.allowedUDPPorts = [ 8000 ];

  systemd.services.vaultwarden = {
    enable = true;

    unitConfig = {
      Description = "Vaultwarden systemd service";
      Documentation = "man:vaultwarden";
      After = "network-online.target";
    };

    serviceConfig = {
      ExecStart = "${pkgs.vaultwarden}/bin/vaultwarden";
      WorkingDirectory = "/var/lib/vaultwarden";
      EnvironmentFile = "/var/lib/vaultwarden/.env";
      Environment = [
        "WEB_VAULT_FOLDER=${pkgs.vaultwarden.webvault}/share/vaultwarden/vault"
      ];
      User = "root";
      Group = "root";
      # Set reasonable connection and process limits
      LimitNOFILE = 1048576;
      LimitNPROC = 64;
    };

    wantedBy = [ "multi-user.target" ];
  };
}
