{ networkTopology, ... }:
{
  services.nginx.streamConfig = ''
    server {
        proxy_pass ${networkTopology.lib.fqdn "pufferpanel-nix"}:8211;
        listen 8211;
      }
  '';
}
