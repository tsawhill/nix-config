{
  services.fail2ban.jails = {
    "vaultwarden-nginx" = {
      settings = {
        enabled = true;
        backend = "polling";
        failregex = ''^<HOST> - -.*"POST.*token.*" (429|400) .*vault.tsawhill.org.*'';
        action = ''iptables-multiport[name=404, port="http,https", protocol=tcp]'';
        logpath = "/var/log/nginx/access.log";
        port = "http, https";
      };
    };
  };
}
