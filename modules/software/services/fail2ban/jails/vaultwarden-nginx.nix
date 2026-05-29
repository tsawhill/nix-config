{
  services.fail2ban.jails = {
    "vaultwarden-nginx" = {
      settings = {
        enabled = true;
        backend = "polling";
        failregex = ''^<HOST> - -.*"POST.*token.*" (429|400) .*vault.tsawhill.org.*'';
        action = ''iptables-multiport[name=vaultwarden-nginx, port="http,https", protocol=tcp]'';
        logpath = "/var/log/nginx/access.log";
        port = "http, https";
      };
    };
  };
}
