{
  services.fail2ban.jails = {
    # mtls-fail.log only gets requests with no cert, a bad one, or a name the proxy doesn't allow.
    "client-cert" = {
      filter.Definition.failregex = "^<HOST> ";
      settings = {
        enabled = true;
        backend = "polling";
        maxretry = 2;
        findtime = "1h";
        action = ''iptables-multiport[name=client-cert, port="http,https", protocol=tcp]'';
        logpath = "/var/log/nginx/mtls-fail.log";
        port = "http, https";
      };
    };
  };
}
