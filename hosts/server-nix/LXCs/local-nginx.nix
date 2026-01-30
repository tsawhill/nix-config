{ self, ... }:
let
  acmeSSHUsers = [ "nginx" ];
in
{
  imports = [
    ./base
    (import "${self}/modules/ssh/keys/acme.nix" acmeSSHUsers)

    "${self}/modules/software/services/nginx/nginx.nix"
    "${self}/modules/software/services/nginx/proxies"
    "${self}/modules/software/services/nginx/streams/minecraft.nix"
  ];
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
    domain = "nextc.tsawhill.org";
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

  networking.hostName = "local-nginx-nix";
}
