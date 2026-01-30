{
  services.fail2ban.jails = {
    "client-cert" = {
      settings = {
        enabled = true;
        backend = "polling";
        failregex = ''.*no required SSL.*client: <HOST>.*'';
        action = ''iptables-multiport[name=404, port="http,https", protocol=tcp]'';
        logpath = "/var/log/nginx/error.log";
        port = "http, https";
      };
    };
  };
}
