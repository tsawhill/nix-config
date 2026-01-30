{ config, pkgs, ... }:
{
  services.nextcloud = {
    enable = true;
    hostName = "nextcloud-nix.lan";
    settings = {
      trusted_domains = [
        "nextc.tsawhill.org"
        "nextcloud-nix.lan"
      ];
      overwritehost = "nextc.tsawhill.org";
      overwriteprotocol = "https";
    };
    package = pkgs.nextcloud32;
    config.adminpassFile = "/etc/nextcloud-admin-pass";
    config.dbtype = "sqlite";
    extraApps = {
      inherit (config.services.nextcloud.package.packages.apps)
        news
        contacts
        calendar
        cookbook
        notes
        # tasks
        ;
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
