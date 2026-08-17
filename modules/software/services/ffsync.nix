{ config, pkgs, ... }:

let
  domain = "ffsync.tsawhill.org";
  port = 5000;
in
{
  networking.firewall.allowedTCPPorts = [ port ];

  # database.createLocally enables services.mysql but picks no package.
  services.mysql.package = pkgs.mariadb;

  # Keep sync data on its own zpool dataset so it is snapshotted and replicated
  # independently of the container root.
  services.mysql.dataDir = "/mnt/zpool/ffsync";

  # On an empty database, firefox-syncserver-setup runs *after* the server (it
  # needs the schema first), so the server caches an unregistered node and 500s
  # every tokenserver request. Restart firefox-syncserver once after the first
  # start. Restoring a populated DB from backup is unaffected.

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
