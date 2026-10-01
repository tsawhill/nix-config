{
  services.fail2ban.jails = {
    "vaultwarden-nginx" = {
      filter.Definition = {
        failregex = ''^<HOST> - -.*"POST.*token.*" (429|400) .*vault.tsawhill.org.*'';
      };
      settings = {
        enabled = true;
        backend = "polling";
        maxretry = 3;
        findtime = "15m";
        action = ''iptables-multiport[name=vaultwarden-nginx, port="http,https", protocol=tcp]'';
        logpath = "/var/log/nginx/access.log";
        port = "http, https";
      };
    };
  };
}
