{ config, pkgs, ... }:

let
  domain = "ffsync.tsawhill.org";
  port = 5000;
in
{
  networking.firewall.allowedTCPPorts = [ port ];

  # database.createLocally enables services.mysql but picks no package.
  services.mysql.package = pkgs.mariadb;

  services.firefox-syncserver = {
    enable = true;
    secrets = config.sops.secrets.ffsync_env.path;
    database.createLocally = true;

    singleNode = {
      enable = true;
      hostname = domain;
      url = "https://${domain}";
      capacity = 5;
      # TLS and the vhost belong to local-nginx-nix.
      enableNginx = false;
      enableTLS = false;
    };

    settings = {
      inherit port;
      # Upstream defaults to 127.0.0.1; nginx proxies in from another container.
      host = "0.0.0.0";
    };
  };
}
