{
  security.acme = {
    acceptTerms = true;
    useRoot = true;
    defaults.group = "root";
    defaults.email = "me@tsawhill.org";
    defaults.dnsResolver = "9.9.9.9:53";
    certs."tsawhill" = {
      domain = "tsawhill.org";
      extraDomainNames = [ "*.tsawhill.org" ];
      dnsProvider = "cloudflare";

      environmentFile = "/root/.cloudflarecreds";
      postRun = "(echo 'The current date and time is: $(date)' && /usr/bin/env scp /var/lib/acme/tsawhill/fullchain.pem /var/lib/acme/tsawhill/key.pem nginx@remote-nginx-nix.lan:/Certs/ && /usr/bin/env ssh nginx@remote-nginx-nix.lan 'chown -R nginx:nginx /Certs && chmod -R 770 /Certs && systemctl restart nginx'; /usr/bin/env scp /var/lib/acme/tsawhill/fullchain.pem /var/lib/acme/tsawhill/key.pem nginx@local-nginx-nix.lan:/Certs/ && /usr/bin/env ssh nginx@local-nginx-nix.lan 'chown -R nginx:nginx /Certs && chmod -R 770 /Certs && systemctl restart nginx') >> /root/postrun.log";
    };
  };
}
