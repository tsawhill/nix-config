{ config, ... }:

{
  my.secrets.cloudflare.ddns.enable = true;

  services.ddclient = {
    enable = true;
    interval = "5min";
    protocol = "cloudflare";
    username = "token";
    passwordFile = config.sops.secrets.cloudflare_ddns_api_token.path;
    zone = "tsawhill.org";
    domains = [
      "tsawhill.org"
      "*.tsawhill.org"
    ];

    # Keep this to IPv4 unless/until the public reverse proxy is meant to
    # receive direct IPv6 traffic too.
    usev6 = "";
    extraConfig = ''
      ttl=1
    '';
  };
}
