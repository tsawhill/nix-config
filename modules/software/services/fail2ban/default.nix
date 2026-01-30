{
  imports = [ ./jails ];
  services.fail2ban = {
    enable = true;
    # Ban IP after 8 failures
    maxretry = 8;
    ignoreIP = [
      # Whitelist some subnets
      "10.0.0.0/8"
      "taylordnsfree.zapto.org" # resolve the IP via DNS
    ];
    bantime = "24h"; # Ban IPs for one day on the first ban
    bantime-increment = {
      enable = true; # Enable increment of bantime after each violation
      multipliers = "1 2 4 8 16 32 64";
      maxtime = "168h"; # Do not ban for more than 1 week
      overalljails = true; # Calculate the bantime based on all the violations
    };
  };
}
