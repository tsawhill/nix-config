{ config, lib, ... }:

let
  cfg = config.my.nginx.publicEdge;
in
{
  imports = [ ./proxies ];

  # Only one host at a time, or the two ddclients fight over the records.
  options.my.nginx.publicEdge.enable =
    lib.mkEnableOption "the public *.tsawhill.org proxies and Cloudflare DDNS";

  config = lib.mkIf cfg.enable {
    # Plain-HTTP requests get forceSSL's redirect.
    networking.firewall.allowedTCPPorts = [ 80 ];

    my.nginx.geoblock.enable = true;
    # Names given to `mtls-ca issue`; per-proxy extras go in mTLSClients.
    my.nginx.mtls.defaultClients = [
      "taylor-desktop-nix"
      "taylor-laptop-nix"
      "taylor-cube-nix"
      "taylor-deck-nix"
      "taylor-phone"
    ];

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

    proxy.authentik = {
      enable = true;
      domain = "auth.tsawhill.org";
    };

    proxy.vaultwarden = {
      enable = true;
      domain = "vault.tsawhill.org";
    };
    proxy.immich = {
      enable = true;
      domain = "immich.tsawhill.org";
    };
    proxy.jellyfin = {
      enable = true;
      domain = "jelly.tsawhill.org";
    };
    proxy.nextcloud = {
      enable = true;
      domain = "nc.tsawhill.org";
    };
    proxy.open-webui = {
      enable = true;
      domain = "llm.tsawhill.org";
      mTLSCert = "mTLS-CA";
    };
    proxy.gotify = {
      enable = true;
      domain = "gotify.tsawhill.org";
      mTLSCert = "mTLS-CA";
    };
    proxy.radarr = {
      enable = true;
      domain = "rad.tsawhill.org";
      mTLSCert = "mTLS-CA";
    };
    proxy.sonarr = {
      enable = true;
      domain = "son.tsawhill.org";
      # mTLSCert = "mTLS-CA";
      enableAuthentik = true;
    };
    proxy.lidarr = {
      enable = true;
      domain = "lid.tsawhill.org";
      mTLSCert = "mTLS-CA";
    };
    proxy.prowlarr = {
      enable = true;
      domain = "pro.tsawhill.org";
      mTLSCert = "mTLS-CA";
    };
    proxy.qui = {
      enable = true;
      domain = "qbit.tsawhill.org";
      mTLSCert = "mTLS-CA";
    };
    proxy.seerr = {
      enable = true;
      domain = "request.tsawhill.org";
    };
    proxy.unifi = {
      enable = true;
      domain = "unifi.tsawhill.org";
      mTLSCert = "mTLS-CA";
    };
    proxy.searx = {
      enable = true;
      domain = "searx.tsawhill.org";
      mTLSCert = "mTLS-CA";
    };
    proxy.homepage = {
      enable = true;
      domain = "home.tsawhill.org";
      mTLSCert = "mTLS-CA";
    };
  };
}
