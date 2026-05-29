{
  services.fail2ban.jails = {
    "nginx-scanner" = {
      settings = {
        enabled = true;
        backend = "polling";
        maxretry = 4;
        findtime = "10m";
        failregex = ''^<HOST> - - \[[^\]]+\] "(GET|POST|HEAD) (/\.env([^ "]*|/[^ "]*)|/(app|src|config|backend|frontend|api|server|client|web|public|private|var)/\.env|/(config|env)|/(config|settings|secrets|credentials|cdp_api_key|env)\.(js|json)|/docker-compose([^ "]*)?\.ya?ml|/(app|main|index|server|bundle|vendor|chunk)(\.bundle)?\.js|/(static/js|dist)/(main|app|bundle)\.js|/cgi-bin/luci/[^ "]*|stager64?|/[A-Za-z0-9]{4,}) HTTP/[0-9.]+" (400|404|444)\b.*'';
        action = ''iptables-multiport[name=nginx-scanner, port="http,https", protocol=tcp]'';
        logpath = "/var/log/nginx/access.log";
        port = "http, https";
      };
    };
  };
}
