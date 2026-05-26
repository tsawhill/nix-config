{ config, ... }:
{
  security.acme = {
    acceptTerms = true;
    defaults.group = "root";
    defaults.email = "me@tsawhill.org";
    defaults.dnsResolver = "9.9.9.9:53";
    certs."tsawhill" = {
      domain = "tsawhill.org";
      extraDomainNames = [ "*.tsawhill.org" ];
      dnsProvider = "cloudflare";

      environmentFile = config.sops.secrets.acme_env.path;
    };
  };
}
