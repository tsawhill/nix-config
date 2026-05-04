{ config, pkgs, ... }:
{
  services.nextcloud = {
    enable = true;
    hostName = "nextcloud-nix.lan";
    home = "/mnt/zpool/nextcloud";
    settings = {
      trusted_domains = [
        "nc.tsawhill.org"
        "nextcloud-nix.lan"
      ];
      allow_local_remote_servers = true;
      overwritehost = "nc.tsawhill.org";
      overwriteprotocol = "https";
    };
    package = pkgs.nextcloud32;
    config.adminpassFile = config.sops.secrets.nextcloud_admin_pass.path;
    config.dbtype = "sqlite";
    appstoreEnable = false;
    extraApps = {
      inherit (config.services.nextcloud.package.packages.apps)
        news
        contacts
        calendar
        cookbook
        notes
        user_oidc
        richdocuments
        tasks
        ;
      shopping_list = pkgs.fetchNextcloudApp {
        appName = "shopping_list";
        appVersion = "1.1.0";
        license = "agpl3Plus";
        hash = "sha256-MJGqOvgTeXY9me/rNGtmk+WS30LU2F/O9XwPwoU1b4o=";
        url = "https://github.com/otherworld-dev/Shopping-List/releases/download/v1.1.0/shopping_list.tar.gz";
        description = "Shared shopping lists for your household";
        homepage = "https://github.com/otherworld-dev/Shopping-List";
      };
    };
    extraAppsEnable = true;
  };
  services.nginx.virtualHosts."nextcloud-nix.lan" = {
    # This override removes the default IPv6 [::] listeners
    # Also only listens on port 80. Put behind a reverse proxy
    listen = [
      {
        addr = "0.0.0.0";
        port = 80;
      }
    ];
  };
  networking.firewall.allowedTCPPorts = [ 80 ];
}
