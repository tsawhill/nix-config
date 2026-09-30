{ config, lib, ... }:
let
  cfg = config.services.fail2ban;
in
{
  imports = [ ./jails ];
  services.fail2ban = {
    enable = true;
    # Default jail policy. Noisy scanner/auth jails override retry windows where
    # the signal is sharper.
    maxretry = 5;
    jails.DEFAULT.settings.findtime = "15m";
    ignoreIP = [
      # Whitelist some subnets
      "10.0.0.0/8"
    ];
    bantime = "24h"; # Ban IPs for one day on the first ban
    bantime-increment = {
      enable = true; # Enable increment of bantime after each violation
      multipliers = "1 2 4 8 16 32 64";
      maxtime = "168h"; # Do not ban for more than 1 week
      overalljails = true; # Calculate the bantime based on all the violations
    };
  };

  # Never ban the home WAN. Its name is a secret, so this re-states jail.local's
  # ignoreip with it appended; jail.d/*.local is read last and wins.
  my.secrets.wireguard.endpoint.enable = true;
  sops.templates."fail2ban-home.local" = {
    content = ''
      [DEFAULT]
      ignoreip = 127.0.0.1/8 ${lib.optionalString config.networking.enableIPv6 "::1"} ${lib.concatStringsSep " " cfg.ignoreIP} ${config.sops.placeholder.wg_remote_endpoint}
    '';
    restartUnits = [ "fail2ban.service" ];
  };
  environment.etc."fail2ban/jail.d/home.local".source =
    config.sops.templates."fail2ban-home.local".path;
}
