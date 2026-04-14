{ self, pkgs, ... }:
let
  acmeSSHUsers = [
    "nginx"
    "root"
  ];
in
{
  imports = [
    ./base
    (import "${self}/modules/ssh/keys/acme.nix" acmeSSHUsers)

    "${self}/modules/software/services/nginx/nginx.nix"
    "${self}/modules/software/services/nginx/proxies"
    "${self}/modules/software/services/nginx/streams/minecraft.nix"
  ];
  users.users.nginx = {
    # This tells NixOS not to use the 'nologin' shell
    shell = pkgs.zsh;
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
  };
  proxy.gotify = {
    enable = true;
    domain = "gotify.tsawhill.org";
  };
  proxy.radarr = {
    enable = true;
    domain = "rad.tsawhill.org";
  };
  proxy.sonarr = {
    enable = true;
    domain = "son.tsawhill.org";
    enableAuthentik = true;
  };
  proxy.lidarr = {
    enable = true;
    domain = "lid.tsawhill.org";
  };
  proxy.prowlarr = {
    enable = true;
    domain = "pro.tsawhill.org";
  };
  proxy.seerr = {
    enable = true;
    domain = "request.tsawhill.org";
  };
  proxy.unifi = {
    enable = true;
    domain = "unifi.tsawhill.org";
  };
  proxy.searx = {
    enable = true;
    domain = "searx.tsawhill.org";
  };

  networking.hostName = "local-nginx-nix";
}
