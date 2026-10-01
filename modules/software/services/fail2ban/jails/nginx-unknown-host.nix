{
  services.fail2ban.jails = {
    "nginx-unknown-host" = {
      filter.Definition = {
        failregex = ''^<HOST> - - \[[^\]]+\] "[^"]*" 444\b.*'';
      };
      settings = {
        enabled = true;
        backend = "polling";
        maxretry = 3;
        findtime = "15m";
        action = ''iptables-multiport[name=nginx-unknown-host, port="http,https", protocol=tcp]'';
        logpath = "/var/log/nginx/unknown-host-access.log";
        port = "http, https";
      };
    };
  };
}
